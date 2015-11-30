#!/usr/bin/env python3

import sys
import re
import xml.etree.ElementTree as et
import abc
from collections import OrderedDict

# Extensions that aren't used often and are hard to override, so we don't support them
EXTENSION_BLACKLIST = set([
	"GL_ARB_vertex_blend",
	"GL_EXT_coordinate_frame",
	"GL_EXT_vertex_shader",
	"GL_EXT_vertex_weighting",
	"GL_ARB_matrix_palette",
])

# Functions that aren't used often and are hard to override, so we stub them out
# with ones that exit the tracee when called.
FUNCTION_PLACEHOLDER = set([
	# CBA to implement sizeof functions for these
	"glBitmap",
	"glColorSubTable",
	"glColorTable",
	"glColorTableParameterfv",
	"glColorTableParameteriv",
	"glConvolutionFilter1D",
	"glConvolutionFilter2D",
	"glConvolutionParameterfv",
	"glConvolutionParameteriv",
	"glDrawPixels",
	"glFogfv",
	"glFogiv",
	"glFogxv",
	"glGetColorTable",
	"glGetColorTableParameterfv",
	"glGetColorTableParameteriv",
	"glGetPolygonStipple",
	"glInterleavedArrays",
	"glLightfv",
	"glLightiv",
	"glLightModelfv",
	"glLightModeliv",
	"glLightModelxv",
	"glLightxv",
	"glPolygonStipple",
	"glTexEnvfv",
	"glTexEnviv",
	"glTexEnvxv",
	"glTexGendv",
	"glTexGenfv",
	"glTexGeniv",
	"glTextureParameterfvEXT",
	"glTextureParameterIivEXT",
	"glTextureParameterIuivEXT",
	"glTextureParameterivEXT",
	"glMultiTexEnvfvEXT",
	"glMultiTexEnvivEXT",
	"glMultiTexGendvEXT",
	"glMultiTexGenfvEXT",
	"glMultiTexGenivEXT",
	"glMaterialfv",
	"glMaterialiv",
	"glMaterialxv",
	"glMultiTexCoordPointerEXT",
	"glMultiTexParameterfvEXT",
	"glMultiTexParameterIivEXT",
	"glMultiTexParameterIuivEXT",
	"glMultiTexParameterivEXT",
	"glMap1d",
	"glMap1f",
	"glMap2d",
	"glMap2f",
	"glTextureImage1DEXT",
	"glTextureImage2DEXT",
	"glTextureImage3DEXT",
	"glTextureSubImage1DEXT",
	"glTextureSubImage2DEXT",
	"glTextureSubImage3DEXT",
	"glSeparableFilter2D",
	"glMultiTexImage1DEXT",
	"glMultiTexImage2DEXT",
	"glMultiTexImage3DEXT",
	"glMultiTexSubImage1DEXT",
	"glMultiTexSubImage2DEXT",
	"glMultiTexSubImage3DEXT",
	
	# Too hard to implement syncing
	"glFenceSync",
	"glDeleteSync",
	"glGetSync",
	"glWaitSync",
	"glClientWaitSync",
	
	# Stuff that needs special handling and is commonly used, but not implemented yet
	"glMapBuffer",
	"glUnmapBuffer",
	"glMapBufferRange",
	"glMapNamedBuffer",
	"glMapNamedBufferRange",
	"glReadPixels",
	
	# Useless in modern programs
	"glFinish",
	
	# derelict bindings don't have these
	"glEdgeFlag",
	"glEdgeFlagv",
	"glClipPlanef",
	"glFrustumf",
	"glOrthof",
])

# Functions whose pointer parameter is an offset and shouldn't be read (despite having a length)
FUNCTION_PTR_OFFSET = set([
	"glColorPointer",
	"glColorPointerEXT",
	"glEdgeFlagPointer",
	"glEdgeFlagPointerEXT",
	"glFogCoordPointer",
	"glFogCoordPointerEXT",
	"glIndexPointer",
	"glIndexPointerEXT",
	"glNormalPointer",
	"glNormalPointerEXT",
	"glSecondaryColorPointer",
	"glSecondaryColorPointerEXT",
	"glTexCoordPointer",
	"glTexCoordPointerEXT",
	"glVertexAttribIPointer",
	"glVertexAttribLPointer",
	"glVertexAttribPointer",
	"glVertexPointer",
	"glVertexPointerEXT",
	"glDrawElements",
	"glDrawElementsBaseVertex",
	"glDrawElementsInstanced",
	"glDrawElementsInstancedBaseVertex",
	"glDrawRangeElements",
	"glDrawRangeElementsBaseVertex",
	"glMultiDrawArraysIndirect",
	"glMultiDrawElementsIndirect",
])

# Functions for which no C wrappers should be generated, because they are implemented specially.
# They still get an enum, however.
FUNCTION_SPECIAL_C = set([
	"glFlush",
	"glGetBufferSubData",
])

class Param:
	"""
	OpenGL function parameter information.
	"""
	def __init__(self, ctype, name, group=None):
		self.ctype = ctype.strip()
		self.name = "ref_" if name == "ref" else name
		self.group = group
		self.function = None
	
	def declaration_c(self):
		return "{0} {1}".format(self.ctype, self.name)
	
	def sizeof_c(self):
		return "sizeof({0})".format(self.name)

class ParamBuffer(Param):
	"""
	Subclass of Param for pointer types to variable-length arrays.
	
	For example, glBufferData takes a pointer to the buffer data, whose length is specified
	by the size parameter.
	"""
	def __init__(self, ctype, name, size, group=None):
		super().__init__(ctype, name, group)
		self.size = size
	
	def sizeof_c(self):
		return "(sizeof(*({0}))*{1})".format(self.name, self.size).replace("COMPSIZE", "COMPSIZE_"+self.function.name+\
			("" if self.function.numBufferParams == 1 else "_"+self.name))
	
	#def sizeof_d(self):
	#	return "(typeof(*{0}).sizeof*{1})".format(self.name, self.size.)
	
	@property
	def dtype(self):
		typ = self.ctype
		if typ.startswith("const"):
			typ = typ[len("const"):]
		if typ.endswith("*"):
			typ = typ[:-len("*")]
		return typ.strip()

class GLFunctionBase(metaclass=abc.ABCMeta):
	"""
	Base class for OpenGL functions.
	"""
	needsID = True
	
	def __init__(self, funcId, name, returnType, params):
		self.id = funcId
		self.name = name
		self.returnType = returnType
		self.params = params
		for p in params:
			p.function = self
	
	def paramsString_c(self):
		if not self.params:
			return "(void)"
		return "(" + ",".join(map(lambda param: param.declaration_c(), self.params)) + ")"
	
	@abc.abstractmethod
	def implementation_c(self):
		pass
	
	@property
	def bufferParams(self):
		return filter(lambda x: isinstance(x, ParamBuffer), self.params)
	
	@property
	def normalParams(self):
		return filter(lambda x: not isinstance(x, ParamBuffer), self.params)
	
	@property
	def numBufferParams(self):
		return sum(map(lambda x: 1 if isinstance(x, ParamBuffer) else 0, self.params))

class GLFunction(GLFunctionBase):
	"""
	Normal OpenGL functions that can be called without any special handling.
	"""
	type = "basic"
	
	def implementation_c(self):
		out  = "EXPORT {0} {1}{2} {{\n".format(self.returnType, self.name, self.paramsString_c())
		
		out += "\tstruct {\n\t\t_lss_gl_command _cmd;\n"
		
		for param in self.params:
			if isinstance(param, ParamBuffer):
				out += "\t\tsize_t _lss_{0}_size;\n".format(param.name)
			else:
				decl = param.declaration_c()
				if "*" not in decl:
					decl = decl.replace("const", "")
				out += "\t\t" + decl + ";\n"
		out += "\t} __attribute__((packed)) _lss_params;\n"
		
		out += "\t_lss_params._cmd = _LSS_GL_{0};\n".format(self.name)
		for param in self.params:
			if isinstance(param, ParamBuffer):
				out += "\t_lss_params._lss_{0}_size = {0} == NULL ? 0 : {1};\n".format(param.name, param.sizeof_c())
			else:
				out += "\t_lss_params.{0} = {0};\n".format(param.name)
		out += "\tqueueGlCommand(&_lss_params, sizeof(_lss_params));\n"
		
		for param in self.bufferParams:
			out += "\tif({0} != NULL) queueGlCommand({0}, {1});\n".format(param.name, param.sizeof_c())
		
		if self.returnType != "void":
			out += "\tflushGlBuffer();\n"
			out += "\t{0} _lss_result;\n".format(self.returnType)
			out += "\treadData(TRACEE_GL_READ_FD, &_lss_result, sizeof(_lss_result));\n"
			out += "\treturn _lss_result;\n"
		
		out += "}\n"
		return out

class GLFunctionAlias(GLFunctionBase):
	"""
	Functions that alias another function.
	"""
	type = "alias"
	needsID = False
	
	def __init__(self, funcId, name, returnType, params, aliasOf):
		super().__init__(funcId, name, returnType, params)
		self.aliasOf = aliasOf
	
	def implementation_c(self):
		return "EXPORT {0} {1}{2} __attribute__((alias(\"{3}\")));\n".format(
			self.returnType,
			self.name,
			self.paramsString_c(),
			self.aliasOf
		)

class GLFunctionPlaceholder(GLFunctionBase):
	"""
	Stub for functions that LSS doesn't have an implementation for.
	"""
	type = "placeholder"
	needsID = False
	
	def implementation_c(self):
		return "EXPORT {0} {1}{2} {{ fail(\"Tracee called {1}, whose wrapper is unimplemented.\"); }}\n".format(
			self.returnType,
			self.name,
			self.paramsString_c()
		)

class GLFunctionGen(GLFunctionBase):
	"""
	glGen* functions.
	"""
	type = "gen"
	
	def __init__(self, funcId, name, returnType, params):
		super().__init__(funcId, name, returnType, params)
		assert returnType == "void", "{0} returns {1}".format(name, returnType)
		assert len(params) == 2
		assert params[0].ctype == "GLsizei"
		assert isinstance(params[1], ParamBuffer)
		assert params[1].ctype == "GLuint *"
	
	def implementation_c(self):
		out  = "EXPORT {0} {1}{2} {{\n".format(self.returnType, self.name, self.paramsString_c())
		
		out += "\tstruct {\n\tint _cmd;\n"
		for param in self.normalParams:
			decl = param.declaration_c()
			if "*" not in decl:
				decl = decl.replace("const", "")
			out += "\t" + decl + ";\n"
		out += "\t} __attribute__((packed)) _lss_params;\n"
		
		out += "\t_lss_params._cmd = (int) _LSS_GL_{0};\n".format(self.name)
		for param in self.normalParams:
			out += "\t_lss_params.{0} = {0};\n".format(param.name)
		out += "\tqueueGlCommand(&_lss_params, sizeof(_lss_params));\n"
		out += "\tflushGlBuffer();\n"
		
		for param in self.bufferParams:
			out += "\treadData(TRACEE_GL_READ_FD, {0}, {1});\n".format(param.name, param.sizeof_c())
		
		out += "}\n"
		return out

class GLFunctionDelete(GLFunction):
	"""
	glDelete* functions.
	"""
	type = "delete"
	
	def __init__(self, funcId, name, returnType, params):
		super().__init__(funcId, name, returnType, params)
		assert returnType == "void", "{0} returns {1}".format(name, returnType)
		assert len(params) == 2
		assert params[0].ctype == "GLsizei"
		assert isinstance(params[1], ParamBuffer)
		assert params[1].ctype == "const GLuint *"

class GLFunctionSpecial(GLFunction):
	"""
	Functions that need special handling. No C wrapper.
	"""
	type = "custom"
	
	def implementation_c(self):
		return ""

def parseFunction(funcElem, funcId):
	"""
	Parses an XML element from the OpenGL spec, and returns a GLFunctionBase subclass
	for that function.
	"""
	
	# Parse return type + name
	proto = funcElem.find("proto")
	returnType = proto.find("ptype")
	returnType = "void" if returnType is None else (proto.text or "") + returnType.text + (returnType.tail or "")
	funcName = proto.find("name").text
	
	# parse parameters
	params = []
	for paramElem in funcElem.findall("param"):
		ptypeElem = paramElem.find("ptype")
		if ptypeElem is None:
			ctype = paramElem.text
		else:
			ctype = (paramElem.text or "") + ptypeElem.text + (ptypeElem.tail or "")
		paramName = paramElem.find("name").text
		
		if "len" in paramElem.attrib and funcName not in FUNCTION_PTR_OFFSET:
			params.append(ParamBuffer(ctype, paramName, paramElem.attrib["len"], paramElem.attrib.get("group")))
		else:
			params.append(Param(ctype, paramName, paramElem.attrib.get("group")))
	
	aliasElem = funcElem.find("alias")
	if funcName in FUNCTION_SPECIAL_C:
		return GLFunctionSpecial(funcId, funcName, returnType, params)
	elif funcName in FUNCTION_PLACEHOLDER or funcName.startswith("glGet") or funcName.endswith("x") or funcName.endswith("xv"):
		return GLFunctionPlaceholder(funcId, funcName, returnType, params)
	elif aliasElem is not None:
		return GLFunctionAlias(funcId, funcName, returnType, params, aliasElem.attrib["name"])
	elif funcName.startswith("glGen") and funcName != "glGenLists" and not funcName.startswith("glGenerate"):
		return GLFunctionGen(funcId, funcName, returnType, params)
	elif funcName.startswith("glDelete") and funcName not in ("glDeleteLists", "glDeleteShader", "glDeleteProgram"):
		return GLFunctionDelete(funcId, funcName, returnType, params)
	else:
		return GLFunction(funcId, funcName, returnType, params)

if __name__ == "__main__":
	import argparse
	
	argparser = argparse.ArgumentParser(description="""
Reads the Khronos OpenGL XML spec from stdin and outputs C overrides for supported GL function.
	""")
	
	argparser.add_argument("out_c", metavar="out.c", type=argparse.FileType("w", encoding="utf-8"))
	argparser.add_argument("out_h", metavar="out.h", type=argparse.FileType("w", encoding="utf-8"))
	argparser.add_argument("out_list", metavar="out.csv", type=argparse.FileType("w", encoding="utf-8"))
	
	args = argparser.parse_args()
	
	root = et.fromstring(sys.stdin.read())
	
	allFunctions = dict((cmdElem.find("proto/name").text, cmdElem) for cmdElem in root.findall("commands/command"))
	
	functionsToGenerate = dict()
	versions = []
	extensions = []
	
	for featureElem in root.findall("feature"):
		versions.append(featureElem.attrib["name"])
		for requireElem in featureElem.findall("require/command"):
			name = requireElem.attrib["name"]
			functionsToGenerate[name] = allFunctions[requireElem.attrib["name"]]
	
	#def shouldIncludeExt(extensionElem):
	#	name = extensionElem.attrib["name"]
	#	if name in EXTENSION_BLACKLIST:
	#		return False
	#	return name.startswith("GL_ARB_") or name.startswith("GL_EXT_")
	
	#for extensionElem in filter(shouldIncludeExt, root.findall("extensions/extension")):
	#	extensions.append(extensionElem.attrib["name"])
	#	for requireElem in extensionElem.findall("require/command"):
	#		functionsToGenerate[requireElem.attrib["name"]] = allFunctions[requireElem.attrib["name"]]
	
	functions = []
	n = 1
	for funcName, funcElem in sorted(functionsToGenerate.items(), key=lambda x: x[0]):
		func = parseFunction(funcElem, n)
		
		functions.append(func)
		n = n + 1
	
	args.out_c.write("""
// NOTE: This file is automatically generated by `gen-gl-wrappers.py`.
#include "gl-generated.h"
#include "glcompsizes.h"

""")
	
	args.out_h.write("""
// NOTE: This file is automatically generated by `gen-gl-wrappers.py`.
#include <stddef.h>
#include <GL/gl.h>
#include <GL/glext.h>

#include "tracee.h"
#include "gl/buffer.h"

typedef int GLclampx; // khronos_int32_t

typedef enum {{
{0}
}} _lss_gl_command;

""".format(
		",\n".join(map(lambda f: "\t_LSS_GL_{0} = {1}".format(f.name, f.id), functions))
	))
	
	for func in functions:
		args.out_c.write(func.implementation_c())
		args.out_list.write(func.name+","+func.type+","+str(func.id)+"\n")
