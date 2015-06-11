
#define CONST __attribute__((const))
#define PURE __attribute__((pure))

#define COMPSIZE_glBindFragDataLocation(name) COMPSIZE_string(name)
#define COMPSIZE_glCallLists(n,type) (n*COMPSIZE_enum(type))
#define COMPSIZE_glClearBufferData(format,type) COMPSIZE_pixel(format,type)
#define COMPSIZE_glClearBufferfv(buffer) (buffer == GL_COLOR ? 4 : 1)
#define COMPSIZE_glClearBufferiv(buffer) (buffer == GL_COLOR ? 4 : 1)
#define COMPSIZE_glClearBufferSubData(format,type) COMPSIZE_pixel(format,type)
#define COMPSIZE_glClearBufferuiv(buffer) (buffer == GL_COLOR ? 4 : 1)
#define COMPSIZE_glClearNamedBufferDataEXT(fmt,type) COMPSIZE_glClearBufferData(fmt,type)
#define COMPSIZE_glClearNamedBufferSubDataEXT(fmt,type) COMPSIZE_glClearBufferSubData(fmt,type)
#define COMPSIZE_glClearTexImage(fmt,type) COMPSIZE_pixel(format,type)
#define COMPSIZE_glClearTexSubImage(fmt,type) COMPSIZE_pixel(format,type)
#define COMPSIZE_glDebugMessageInsert(label,length) (length < 0 ? COMPSIZE_string(label) : length)
#define COMPSIZE_glDepthRangeArrayv(count) (count*2)
#define COMPSIZE_glMultiDrawArrays_count(drawcount) drawcount
#define COMPSIZE_glMultiDrawArrays_first(count) drawcount // the count array is passed in here for some reason
#define COMPSIZE_glMultiDrawElements_count(drawcount) drawcount
#define COMPSIZE_glMultiDrawElements_indices(drawcount) drawcount
#define COMPSIZE_glMultiDrawElementsBaseVertex_basevertex(drawcount) drawcount
#define COMPSIZE_glMultiDrawElementsBaseVertex_count(drawcount) drawcount
#define COMPSIZE_glMultiDrawElementsBaseVertex_indices(drawcount) drawcount
#define COMPSIZE_glNamedBufferDataEXT(size) size
#define COMPSIZE_glNamedBufferSubData(size) size
#define COMPSIZE_glObjectLabel(label,length) (length < 0 ? COMPSIZE_string(label) : length)
#define COMPSIZE_glObjectLabel(label,length) (length < 0 ? COMPSIZE_string(label) : length)
#define COMPSIZE_glObjectPtrLabel(label,length) (length < 0 ? COMPSIZE_string(label) : length)
#define COMPSIZE_glPatchParameterfv(pname) (pname == GL_PATCH_DEFAULT_OUTER_LEVEL ? 4 : 2)
#define COMPSIZE_glPointParameterfv(pname) (pname == GL_POINT_DISTANCE_ATTENUATION ? 3 : 1)
#define COMPSIZE_glPointParameteriv(pname) (pname == GL_POINT_DISTANCE_ATTENUATION ? 3 : 1)
#define COMPSIZE_glPointParameterxv(pname) (pname == GL_POINT_DISTANCE_ATTENUATION ? 3 : 1)
#define COMPSIZE_glPushDebugGroup(label,length) (length < 0 ? COMPSIZE_string(label) : length)
#define COMPSIZE_glReadPixels(format,type,width,height) 0 // TODO: properly implement
#define COMPSIZE_glSamplerParameterfv(pname) (pname == GL_TEXTURE_BORDER_COLOR ? 4 : 0)
#define COMPSIZE_glSamplerParameterIiv(pname) (pname == GL_TEXTURE_BORDER_COLOR ? 4 : 0)
#define COMPSIZE_glSamplerParameterIuiv(pname) (pname == GL_TEXTURE_BORDER_COLOR ? 4 : 0)
#define COMPSIZE_glSamplerParameteriv(pname) (pname == GL_TEXTURE_BORDER_COLOR ? 4 : 0)
#define COMPSIZE_glScissorArrayv(count) (count*4)
#define COMPSIZE_glTexParameterfv(pname) ((pname == GL_TEXTURE_BORDER_COLOR || pname == GL_TEXTURE_SWIZZLE_RGBA) ? 4 : 1)
#define COMPSIZE_glTexParameterIiv(pname) ((pname == GL_TEXTURE_BORDER_COLOR || pname == GL_TEXTURE_SWIZZLE_RGBA) ? 4 : 1)
#define COMPSIZE_glTexParameterIuiv(pname) ((pname == GL_TEXTURE_BORDER_COLOR || pname == GL_TEXTURE_SWIZZLE_RGBA) ? 4 : 1)
#define COMPSIZE_glTexParameteriv(pname) ((pname == GL_TEXTURE_BORDER_COLOR || pname == GL_TEXTURE_SWIZZLE_RGBA) ? 4 : 1)
#define COMPSIZE_glTexParameterxv(pname) ((pname == GL_TEXTURE_BORDER_COLOR || pname == GL_TEXTURE_SWIZZLE_RGBA) ? 4 : 1)
#define COMPSIZE_glViewportArrayv(count) (count*4)

#define COMPSIZE_glTexImage1D(format,type,width) (COMPSIZE_pixel(format,type)*width) // TODO: alignment support
#define COMPSIZE_glTexImage2D(format,type,width,height) (COMPSIZE_pixel(format,type)*width*height)
#define COMPSIZE_glTexImage3D(format,type,width,height,depth) (COMPSIZE_pixel(format,type)*width*height*depth)

#define COMPSIZE_glTexSubImage1D(format,type,width) (COMPSIZE_pixel(format,type)*width)
#define COMPSIZE_glTexSubImage2D(format,type,width,height) (COMPSIZE_pixel(format,type)*width*height)
#define COMPSIZE_glTexSubImage3D(format,type,width,height,depth) (COMPSIZE_pixel(format,type)*width*height*depth)


static PURE size_t COMPSIZE_string(const char* str) {
	size_t size = 0;
	while(str[size++]);
	return size;
}

/// Converts a type enumeration (ex. GL_BYTE, GL_INT) to a size.
static CONST size_t COMPSIZE_enum(GLenum en) {
	switch(en) {
	case GL_BYTE:
	case GL_UNSIGNED_BYTE:
		return sizeof(GLbyte);
	case GL_SHORT:
	case GL_UNSIGNED_SHORT:
		return sizeof(GLshort);
	case GL_INT:
	case GL_UNSIGNED_INT:
		return sizeof(GLint);
	case GL_2_BYTES:
		return 2;
	case GL_3_BYTES:
		return 3;
	case GL_4_BYTES:
		return 4;
	case GL_HALF_FLOAT:
		return sizeof(GLhalf);
	case GL_FLOAT:
		return sizeof(GLfloat);
	case GL_DOUBLE:
		return sizeof(GLdouble);
	
	default:
		// TODO: log here
		return 0;
	}
}

/// Converts a pixel format/type pair to a per-pixel size.
static CONST size_t COMPSIZE_pixel(GLenum format, GLenum type) {
	// Packed values have the same size regardless of the format.
	// Table 8.10 of the compatibility spec
	switch(type) {
	case GL_UNSIGNED_BYTE_3_3_2:
	case GL_UNSIGNED_BYTE_2_3_3_REV:
		return sizeof(GLubyte);
	case GL_UNSIGNED_SHORT_5_6_5:
	case GL_UNSIGNED_SHORT_5_6_5_REV:
	case GL_UNSIGNED_SHORT_4_4_4_4:
	case GL_UNSIGNED_SHORT_4_4_4_4_REV:
	case GL_UNSIGNED_SHORT_5_5_5_1:
	case GL_UNSIGNED_SHORT_1_5_5_5_REV:
		return sizeof(GLushort);
	case GL_UNSIGNED_INT_8_8_8_8:
	case GL_UNSIGNED_INT_8_8_8_8_REV:
	case GL_UNSIGNED_INT_10_10_10_2:
	case GL_UNSIGNED_INT_2_10_10_10_REV:
	case GL_UNSIGNED_INT_24_8:
	case GL_UNSIGNED_INT_5_9_9_9_REV:
		return sizeof(GLuint);
	// TODO: what is GL_FLOAT_32_UNSIGNED_INT_24_8_REV
	}
	
	size_t sizePerComponent = COMPSIZE_enum(type);
	switch(format) {
	// Table 8.8 of the compatibility spec
	case GL_RED:
	case GL_GREEN:
	case GL_BLUE:
	case GL_RED_INTEGER:
	case GL_GREEN_INTEGER:
	case GL_BLUE_INTEGER:
	case GL_DEPTH_COMPONENT:
	case GL_STENCIL_INDEX:
	case GL_DEPTH_STENCIL:
	case GL_COLOR_INDEX:
	case GL_ALPHA:
	case GL_ALPHA_INTEGER:
	case GL_LUMINANCE:
		return sizePerComponent;
	case GL_RG:
	case GL_RG_INTEGER:
	case GL_LUMINANCE_ALPHA:
		return sizePerComponent*2;
	case GL_RGB:
	case GL_BGR:
	case GL_RGB_INTEGER:
	case GL_BGR_INTEGER:
		return sizePerComponent*3;
	case GL_RGBA:
	case GL_BGRA:
	case GL_RGBA_INTEGER:
	case GL_BGRA_INTEGER:
		return sizePerComponent*4;
	default:
		// TODO: log here
		return 0;
	}
}

#undef CONST
#undef PURE
