/* llvmpipe's clipper and the values a shader asks for without perspective
 * (issues 479 and 493). A triangle with one corner behind the eye, drawn by
 * this core's Mesa, whose value at each corner is the corner's own position
 * on the screen (x/W, y/W), as Supermodel's New3D passes its corners. Where
 * the triangle is drawn, the value must be the pixel's own position. For a
 * corner just behind the eye (W a little below 0) that position is enormous,
 * and the clipper's blend of the two ends cancelled to noise: 3 pixels off at
 * W = -0.000001, 8 at -0.0000001, which smeared floors near the camera. For
 * each W given it prints how far off the worst pixel is, and quits with 1
 * when any is more than a hundredth of a pixel off or the triangle was not
 * drawn.
 *   noperspective-clip <W>... */
#include <GL/osmesa.h>
#include <GL/glext.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define W 256
#define H 256

#define GLF(type, name) static type name;
GLF(PFNGLCREATESHADERPROC, glCreateShader_)
GLF(PFNGLSHADERSOURCEPROC, glShaderSource_)
GLF(PFNGLCOMPILESHADERPROC, glCompileShader_)
GLF(PFNGLGETSHADERIVPROC, glGetShaderiv_)
GLF(PFNGLGETSHADERINFOLOGPROC, glGetShaderInfoLog_)
GLF(PFNGLCREATEPROGRAMPROC, glCreateProgram_)
GLF(PFNGLATTACHSHADERPROC, glAttachShader_)
GLF(PFNGLLINKPROGRAMPROC, glLinkProgram_)
GLF(PFNGLUSEPROGRAMPROC, glUseProgram_)
GLF(PFNGLGENVERTEXARRAYSPROC, glGenVertexArrays_)
GLF(PFNGLBINDVERTEXARRAYPROC, glBindVertexArray_)
GLF(PFNGLGENBUFFERSPROC, glGenBuffers_)
GLF(PFNGLBINDBUFFERPROC, glBindBuffer_)
GLF(PFNGLBUFFERDATAPROC, glBufferData_)
GLF(PFNGLVERTEXATTRIBPOINTERPROC, glVertexAttribPointer_)
GLF(PFNGLENABLEVERTEXATTRIBARRAYPROC, glEnableVertexAttribArray_)
GLF(PFNGLGENFRAMEBUFFERSPROC, glGenFramebuffers_)
GLF(PFNGLBINDFRAMEBUFFERPROC, glBindFramebuffer_)
GLF(PFNGLFRAMEBUFFERTEXTURE2DPROC, glFramebufferTexture2D_)
#define LOAD(name) name##_ = (void *)OSMesaGetProcAddress(#name); if (!name##_) { fprintf(stderr, "no %s\n", #name); return 2; }

static const char *vs =
	"#version 330 core\n"
	"layout(location = 0) in vec4 pos;\n"
	"noperspective out vec2 screen;\n"
	"void main() { gl_Position = pos; screen = pos.xy / pos.w; }\n";
static const char *fs =
	"#version 330 core\n"
	"noperspective in vec2 screen;\n"
	"out vec4 colour;\n"
	"void main() { colour = vec4(screen, 1.0, 1.0); }\n";

static unsigned shader(GLenum kind, const char *src)
{
	unsigned s = glCreateShader_(kind);
	glShaderSource_(s, 1, &src, NULL);
	glCompileShader_(s);
	int ok = 0;
	glGetShaderiv_(s, GL_COMPILE_STATUS, &ok);
	if (!ok) { char log[2048]; glGetShaderInfoLog_(s, sizeof log, NULL, log); fprintf(stderr, "%s\n", log); exit(2); }
	return s;
}

int main(int argc, char **argv)
{
	const int attribs[] = {OSMESA_FORMAT, OSMESA_RGBA, OSMESA_DEPTH_BITS, 0, OSMESA_PROFILE, OSMESA_CORE_PROFILE,
		OSMESA_CONTEXT_MAJOR_VERSION, 3, OSMESA_CONTEXT_MINOR_VERSION, 3, 0};
	OSMesaContext ctx = OSMesaCreateContextAttribs(attribs, NULL);
	if (!ctx) { fprintf(stderr, "no context\n"); return 2; }
	static unsigned char back[W * H * 4];
	if (!OSMesaMakeCurrent(ctx, back, GL_UNSIGNED_BYTE, W, H)) { fprintf(stderr, "not current\n"); return 2; }
	LOAD(glCreateShader) LOAD(glShaderSource) LOAD(glCompileShader) LOAD(glGetShaderiv) LOAD(glGetShaderInfoLog)
	LOAD(glCreateProgram) LOAD(glAttachShader) LOAD(glLinkProgram) LOAD(glUseProgram) LOAD(glGenVertexArrays)
	LOAD(glBindVertexArray) LOAD(glGenBuffers) LOAD(glBindBuffer) LOAD(glBufferData) LOAD(glVertexAttribPointer)
	LOAD(glEnableVertexAttribArray) LOAD(glGenFramebuffers) LOAD(glBindFramebuffer)
	LOAD(glFramebufferTexture2D) 
	

	unsigned prog = glCreateProgram_();
	glAttachShader_(prog, shader(GL_VERTEX_SHADER, vs));
	glAttachShader_(prog, shader(GL_FRAGMENT_SHADER, fs));
	glLinkProgram_(prog);
	glUseProgram_(prog);
	unsigned tex, fbo, vao, vbo;
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, W, H, 0, GL_RGBA, GL_FLOAT, NULL);
	glGenFramebuffers_(1, &fbo);
	glBindFramebuffer_(GL_FRAMEBUFFER, fbo);
	glFramebufferTexture2D_(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
	glViewport(0, 0, W, H);
	glGenVertexArrays_(1, &vao);
	glBindVertexArray_(vao);
	glGenBuffers_(1, &vbo);
	glBindBuffer_(GL_ARRAY_BUFFER, vbo);
	glVertexAttribPointer_(0, 4, GL_FLOAT, GL_FALSE, 0, NULL);
	glEnableVertexAttribArray_(0);

	static float px[W * H * 4];
	int worst_case = 0;
	for (int a = 1; a < argc; a++)
	{
		const float wb = (float)atof(argv[a]);
		/* two corners in front, low on the screen; the third ahead of the
		 * eye on the floor, its w just below zero (behind the eye); z inside
		 * the depth range so only the w clip applies */
		const float tri[12] = {
			-0.6f, -0.8f, 0.0f, 1.0f,
			 0.7f, -0.9f, 0.0f, 1.0f,
			 0.3f * wb + 0.05f, 0.5f, 0.0f, wb,
		};
		glBufferData_(GL_ARRAY_BUFFER, sizeof tri, tri, GL_STATIC_DRAW);
		glClearColor(0, 0, 0, 0);
		glClear(GL_COLOR_BUFFER_BIT);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		glFinish();
		glReadPixels(0, 0, W, H, GL_RGBA, GL_FLOAT, px);
		double worst = 0;
		int drawn = 0, bad = 0;
		for (int y = 0; y < H; y++)
			for (int x = 0; x < W; x++)
			{
				const float *p = px + (y * W + x) * 4;
				if (p[2] != 1.0f) continue;
				drawn++;
				/* the pixel's centre in NDC */
				const double ex = (x + 0.5) / W * 2 - 1, ey = (y + 0.5) / H * 2 - 1;
				const double d = fmax(fabs(p[0] - ex) * W / 2, fabs(p[1] - ey) * H / 2);
				if (!(d <= worst)) worst = isfinite(d) ? d : 1e30;
				if (!(d <= 0.01)) bad++;
			}
		printf("w %-10g drawn %6d pixels, worst %10.3g pixels off, %6d more than 0.01 off\n", wb, drawn, worst, bad);
		if (bad || drawn < 1000) worst_case = 1;
	}
	OSMesaDestroyContext(ctx);
	return worst_case;
}
