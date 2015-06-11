#!/usr/bin/env python3

import sys
import re
import xml.etree.ElementTree as et
import logging
import abc
from collections import OrderedDict

EXTENSION_BLACKLIST = set([
	"GL_EXT_vertex_shader",
	"GL_KHR_debug",
])

class Param:
	def __init__(self, ctype, name):
		self.ctype = ctype
		self.name = name
	
	def declaration_c(self):
		return "{0} {1}".format(self.ctype, self.name)
	
	def sizeof_c(self):
		return "sizeof({0})".format(self.name)

class ParamBuffer(Param):
	def __init__(self, ctype, name, size):
		super().__init__(ctype, name)
		self.size = size
	
	def sizeof_c(self):
		return "(sizeof(*({0}))*{1})".format(self.name, self.size)

class GLFunctionBase(metaclass=abc.ABCMeta):
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
			out += "\t_lss_write({0}, {1});\n".format(param.name, param.sizeof_c())
		
		if self.returnType != "void":
			out += "\t{0} _lss_result;\n".format(self.returnType)
			out += "\t_lss_read(&_lss_result, sizeof(_lss_result));\n"
			out += "\treturn _lss_result;\n"
		
		out += "}\n"
		return out
	
	def implementation_d(self):
		pass

class GLFunctionAlias(GLFunctionBase):
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
		
		if "len" in paramElem.attrib:
			if "COMPSIZE" in paramElem.attrib["len"]:
				print(funcName, paramName, paramElem.attrib["len"])
			
			params.append(ParamBuffer(ctype, paramName, paramElem.attrib["len"]))
		else:
			params.append(Param(ctype, paramName))
	
	# Return either an alias or normal function
	aliasElem = funcElem.find("alias")
	if aliasElem is None:
		return GLFunction(funcName, returnType, params)
	else:
		return GLFunctionAlias(funcName, returnType, params, aliasElem.attrib["name"])

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
	
	for extensionElem in (x for x in root.findall("extensions/extension") if (x.attrib["name"].startswith("GL_ARB_") or x.attrib["name"].startswith("GL_EXT_")) and x.attrib["name"] not in EXTENSION_BLACKLIST):
		extensions.append(extensionElem.attrib["name"])
		for requireElem in extensionElem.findall("require/command"):
			functions[requireElem.attrib["name"]] = allFunctions[requireElem.attrib["name"]]
	
	#print(versions)
	#print(extensions)
	#print(functions.keys())
	
	args.out_c.write("""
#include <GL/gl.h>
#include <GL/glext.h>

void _lss_write(const void*, size_t);
void _lss_read(void*, size_t);
//size_t COMPSIZE(size_t,...);
#define COMPSIZE(...) 1

typedef int GLclampx;

typedef enum {{
{0}
}} _lss_gl_command;

""".format(
		",\n".join(map(lambda name: "\t_LSS_GL_{0}".format(name), sorted(functions.keys())))
	))
	
	for funcName, funcElem in sorted(functions.items(), key=lambda x: x[0]):
		func = parseFunction(funcElem)
		args.out_c.write(func.implementation_c())
