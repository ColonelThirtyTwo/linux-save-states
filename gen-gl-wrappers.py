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
FUNCTION_STUB = set([
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
	
	"glReadPixels", # TODO: Probably need to implement this
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

class Param:
	def __init__(self, ctype, name, group=None):
		self.ctype = ctype
		self.name = name
		self.group = group
	
	def declaration_c(self):
		return "{0} {1}".format(self.ctype, self.name)
	
	def sizeof_c(self):
		return "sizeof({0})".format(self.name)

class ParamBuffer(Param):
	def __init__(self, ctype, name, size, group=None):
		super().__init__(ctype, name, group)
		self.size = size
	
	def sizeof_c(self):
		return "(sizeof(*({0}))*{1})".format(self.name, self.size)

class GLFunctionBase(metaclass=abc.ABCMeta):
	needsID = True
	
	def __init__(self, name, returnType, params):
		self.name = name
		self.returnType = returnType
		self.params = params
	
	def paramsString_c(self):
		if not self.params:
			return "(void)"
		return "(" + ",".join(map(lambda param: param.declaration_c(), self.params)) + ")"
	
	@abc.abstractmethod
	def implementation_c(self):
		pass
	
	@abc.abstractmethod
	def implementation_d(self):
		pass

class GLFunction(GLFunctionBase):
	def implementation_c(self):
		out  = "{0} {1}{2} {{\n".format(self.returnType, self.name, self.paramsString_c())
		
		out += "\tstruct {\n\t_lss_gl_command _cmd;\n"
		
		numBufferParams = 0
		for param in self.params:
			if isinstance(param, ParamBuffer):
				out += "\tint _lss_has_{0};\n".format(param.name)
				numBufferParams += 1
			else:
				decl = param.declaration_c()
				if "*" not in decl:
					decl = decl.replace("const", "")
				out += "\t" + decl + ";\n"
		out += "\t} __attribute__((packed)) _lss_params;\n"
		
		out += "\t_lss_params._cmd = _LSS_GL_{0};\n".format(self.name)
		for param in self.params:
			if isinstance(param, ParamBuffer):
				out += "\t_lss_params._lss_has_{0} = {0} != NULL;\n".format(param.name)
			else:
				out += "\t_lss_params.{0} = {0};\n".format(param.name)
		out += "\t_lss_write(&_lss_params, sizeof(_lss_params));\n"
		
		for param in self.params:
			if isinstance(param, ParamBuffer):
				out += "\tif({0} != NULL) _lss_write({0}, {1});\n".format(param.name,
					param.sizeof_c().replace("COMPSIZE", "COMPSIZE_"+self.name+("" if numBufferParams <= 1 else ("_" + param.name)))
				)
		
		if self.returnType != "void":
			out += "\t{0} _lss_result;\n".format(self.returnType)
			out += "\t_lss_read(&_lss_result, sizeof(_lss_result));\n"
			out += "\treturn _lss_result;\n"
		
		out += "}\n"
		return out
	
	def implementation_d(self):
		pass

class GLFunctionAlias(GLFunctionBase):
	needsID = False
	
	def __init__(self, name, returnType, params, aliasOf):
		super().__init__(name, returnType, params)
		self.aliasOf = aliasOf
	
	def implementation_c(self):
		return "{0} {1}{2} __attribute__((alias(\"{3}\")));\n".format(
			self.returnType,
			self.name,
			self.paramsString_c(),
			self.aliasOf
		)
	
	def implementation_d(self):
		pass

class GLFunctionStub(GLFunctionBase):
	needsID = False
	
	def implementation_c(self):
		return "{0} {1}{2} {{ fail(\"{1} called.\"); }}\n".format(
			self.returnType,
			self.name,
			self.paramsString_c()
		)
	
	def implementation_d(self):
		pass

class GLFunctionGen(GLFunctionBase):
	def __init__(self, name, returnType, params):
		super().__init__(name, returnType, params)
		assert returnType == "void", "{0} returns {1}".format(name, returnType)
	
	def implementation_c(self):
		out  = "{0} {1}{2} {{\n".format(self.returnType, self.name, self.paramsString_c())
		
		out += "\tstruct {\n\t_lss_gl_command _cmd;\n"
		for param in self.params:
			if isinstance(param, ParamBuffer):
				continue
			
			decl = param.declaration_c()
			if "*" not in decl:
				decl = decl.replace("const", "")
			out += "\t" + decl + ";\n"
		out += "\t} __attribute__((packed)) _lss_params;\n"
		
		out += "\t_lss_params._cmd = _LSS_GL_{0};\n".format(self.name)
		for param in self.params:
			if isinstance(param, ParamBuffer):
				continue
			out += "\t_lss_params.{0} = {0};\n".format(param.name)
		out += "\t_lss_write(&_lss_params, sizeof(_lss_params));\n"
		
		for param in self.params:
			if not isinstance(param, ParamBuffer):
				continue
			out += "\t_lss_read({0}, {1});\n".format(param.name, param.sizeof_c())
		
		out += "}\n"
		return out
	
	def implementation_d(self):
		pass

def parseFunction(funcElem):
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
	if aliasElem is not None:
		return GLFunctionAlias(funcName, returnType, params, aliasElem.attrib["name"])
	elif funcName in FUNCTION_STUB :
		return GLFunctionStub(funcName, returnType, params)
	elif funcName.startswith("glGen") and funcName != "glGenLists":
		return GLFunctionGen(funcName, returnType, params)
	else:
		return GLFunction(funcName, returnType, params)

if __name__ == "__main__":
	import argparse
	
	argparser = argparse.ArgumentParser(description="""
Reads the Khronos OpenGL XML spec from stdin and outputs C overrides and D handling
code for the functions.
	""")
	
	argparser.add_argument("out_d", metavar="out.d", type=argparse.FileType("w", encoding="utf-8"))
	argparser.add_argument("out_c", metavar="out.c", type=argparse.FileType("w", encoding="utf-8"))
	
	args = argparser.parse_args()
	
	root = et.fromstring(sys.stdin.read())
	
	allFunctions = dict((cmdElem.find("proto/name").text, cmdElem) for cmdElem in root.findall("commands/command"))
	
	functions = dict()
	versions = []
	extensions = []
	
	for featureElem in root.findall("feature"):
		versions.append(featureElem.attrib["name"])
		for requireElem in featureElem.findall("require/command"):
			functions[requireElem.attrib["name"]] = allFunctions[requireElem.attrib["name"]]
	
	def shouldIncludeExt(extensionElem):
		name = extensionElem.attrib["name"]
		if name in EXTENSION_BLACKLIST:
			return False
		return name.startswith("GL_ARB_") or name.startswith("GL_EXT_")
	
	for extensionElem in filter(shouldIncludeExt, root.findall("extensions/extension")):
		extensions.append(extensionElem.attrib["name"])
		for requireElem in extensionElem.findall("require/command"):
			functions[requireElem.attrib["name"]] = allFunctions[requireElem.attrib["name"]]
	
	args.out_c.write("""
#include <stddef.h>
#include <GL/gl.h>
#include <GL/glext.h>

void _lss_write(const void*, size_t);
void _lss_read(void*, size_t);
__attribute__((noreturn)) void fail(const char*);

typedef int GLclampx; // khronos_int32_t

#include "glcompsizes.h"

typedef enum {{
{0}
}} _lss_gl_command;

""".format(
		",\n".join(map(lambda name: "\t_LSS_GL_{0}".format(name), sorted(functions.keys())))
	))
	
	for funcName, funcElem in sorted(functions.items(), key=lambda x: x[0]):
		# TESING: REMOVE THIS
		if funcName.startswith("glGet"):
			continue
		
		func = parseFunction(funcElem)
		args.out_c.write(func.implementation_c())
