#include "hdrbuffers.h"
#include "wlcolor.h"

#include <QtCore/QList>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <wayland-client.h>
#include "protocols/linux-dmabuf-v1-client.h"

#include <dlfcn.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/mman.h>
#include <unistd.h>

#include <algorithm>
#include <climits>
#include <cstring>

namespace {

constexpr uint32_t fourcc(char a, char b, char c, char d)
{
    return uint32_t(uint8_t(a)) | (uint32_t(uint8_t(b)) << 8) | (uint32_t(uint8_t(c)) << 16) | (uint32_t(uint8_t(d)) << 24);
}
// The same codes for dmabuf and (beyond the first two) shm.
constexpr uint32_t kXB30 = fourcc('X', 'B', '3', '0'); // x:B:G:R 2:10:10:10, R lowest
constexpr uint32_t kXR30 = fourcc('X', 'R', '3', '0'); // x:R:G:B 2:10:10:10, B lowest
constexpr uint32_t kXB24 = fourcc('X', 'B', '2', '4'); // bytes R G B x
constexpr uint32_t kXR24 = fourcc('X', 'R', '2', '4'); // bytes B G R x
constexpr uint32_t kShmXrgb8888 = 1;                  // wl_shm's own code for XR24
constexpr uint64_t kModInvalid = 0x00ffffffffffffffULL;
constexpr uint32_t kGbmUseRendering = 1u << 2;

constexpr unsigned int kGlTexture2d = 0x0DE1, kGlFramebuffer = 0x8D40, kGlReadFramebuffer = 0x8CA8,
                       kGlColorAttachment0 = 0x8CE0, kGlFramebufferComplete = 0x8CD5, kGlNearest = 0x2600,
                       kGlTextureMinFilter = 0x2801, kGlTextureMagFilter = 0x2800, kGlRgba = 0x1908,
                       kGlBgra = 0x80E1, kGlUnsignedByte = 0x1401, kGlUnsignedInt2101010Rev = 0x8368,
                       kGlRgb10A2 = 0x8059, kGlRgba8 = 0x8058, kGlPackAlignment = 0x0D05;

QString name(uint32_t f)
{
    if (f == kShmXrgb8888) f = kXR24;
    return QString::fromLatin1(QByteArray(reinterpret_cast<const char *>(&f), 4));
}
bool tenBit(uint32_t f) { return f == kXB30 || f == kXR30; }

// GL through EGL (no link to libGL).
struct Gl
{
    void (*genFramebuffers)(int, unsigned int *) = nullptr;
    void (*deleteFramebuffers)(int, const unsigned int *) = nullptr;
    void (*genTextures)(int, unsigned int *) = nullptr;
    void (*deleteTextures)(int, const unsigned int *) = nullptr;
    void (*bindTexture)(unsigned int, unsigned int) = nullptr;
    void (*texImage2D)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void *) = nullptr;
    void (*texParameteri)(unsigned int, unsigned int, int) = nullptr;
    void (*framebufferTexture2D)(unsigned int, unsigned int, unsigned int, unsigned int, int) = nullptr;
    unsigned int (*checkFramebufferStatus)(unsigned int) = nullptr;
    void (*bindFramebuffer)(unsigned int, unsigned int) = nullptr;
    void (*readPixels)(int, int, int, int, unsigned int, unsigned int, void *) = nullptr;
    void (*pixelStorei)(unsigned int, int) = nullptr;
    void (*finish)() = nullptr;
    void (*imageTargetTexture2D)(unsigned int, void *) = nullptr; // glEGLImageTargetTexture2DOES
    bool loaded = false;
    bool load()
    {
        if (loaded) return true;
#define GC_GL(f, n) f = reinterpret_cast<decltype(f)>(eglGetProcAddress(n))
        GC_GL(genFramebuffers, "glGenFramebuffers");
        GC_GL(deleteFramebuffers, "glDeleteFramebuffers");
        GC_GL(genTextures, "glGenTextures");
        GC_GL(deleteTextures, "glDeleteTextures");
        GC_GL(bindTexture, "glBindTexture");
        GC_GL(texImage2D, "glTexImage2D");
        GC_GL(texParameteri, "glTexParameteri");
        GC_GL(framebufferTexture2D, "glFramebufferTexture2D");
        GC_GL(checkFramebufferStatus, "glCheckFramebufferStatus");
        GC_GL(bindFramebuffer, "glBindFramebuffer");
        GC_GL(readPixels, "glReadPixels");
        GC_GL(pixelStorei, "glPixelStorei");
        GC_GL(finish, "glFinish");
        GC_GL(imageTargetTexture2D, "glEGLImageTargetTexture2DOES");
#undef GC_GL
        loaded = genFramebuffers && deleteFramebuffers && genTextures && deleteTextures && bindTexture && texImage2D
            && texParameteri && framebufferTexture2D && checkFramebufferStatus && bindFramebuffer && readPixels
            && pixelStorei && finish;
        return loaded;
    }
};
Gl gl;

// libgbm, loaded only when dmabuf is tried (Mesa's; it picks NVIDIA's
// backend by itself): no link, no new dependency.
struct Gbm
{
    void *lib = nullptr;
    gbm_device *(*createDevice)(int) = nullptr;
    void (*deviceDestroy)(gbm_device *) = nullptr;
    gbm_bo *(*boCreate)(gbm_device *, uint32_t, uint32_t, uint32_t, uint32_t) = nullptr;
    gbm_bo *(*boCreateWithModifiers)(gbm_device *, uint32_t, uint32_t, uint32_t, const uint64_t *, unsigned int) = nullptr;
    void (*boDestroy)(gbm_bo *) = nullptr;
    int (*boGetFd)(gbm_bo *) = nullptr;
    uint64_t (*boGetModifier)(gbm_bo *) = nullptr;
    int (*boGetPlaneCount)(gbm_bo *) = nullptr;
    uint32_t (*boGetStrideForPlane)(gbm_bo *, int) = nullptr;
    uint32_t (*boGetOffset)(gbm_bo *, int) = nullptr;
    bool load()
    {
        if (lib) return true;
        lib = dlopen("libgbm.so.1", RTLD_NOW | RTLD_LOCAL);
        if (!lib) return false;
#define GC_GBM(f, n) f = reinterpret_cast<decltype(f)>(dlsym(lib, n))
        GC_GBM(createDevice, "gbm_create_device");
        GC_GBM(deviceDestroy, "gbm_device_destroy");
        GC_GBM(boCreate, "gbm_bo_create");
        GC_GBM(boCreateWithModifiers, "gbm_bo_create_with_modifiers");
        GC_GBM(boDestroy, "gbm_bo_destroy");
        GC_GBM(boGetFd, "gbm_bo_get_fd");
        GC_GBM(boGetModifier, "gbm_bo_get_modifier");
        GC_GBM(boGetPlaneCount, "gbm_bo_get_plane_count");
        GC_GBM(boGetStrideForPlane, "gbm_bo_get_stride_for_plane");
        GC_GBM(boGetOffset, "gbm_bo_get_offset");
#undef GC_GBM
        if (createDevice && deviceDestroy && boCreate && boDestroy && boGetFd && boGetModifier && boGetPlaneCount
            && boGetStrideForPlane && boGetOffset) {
            return true;
        }
        dlclose(lib);
        lib = nullptr;
        return false;
    }
};
Gbm gbm;

using CreateImage = EGLImageKHR (*)(EGLDisplay, EGLContext, EGLenum, EGLClientBuffer, const EGLint *);
using DestroyImage = EGLBoolean (*)(EGLDisplay, EGLImageKHR);
using QueryModifiers = EGLBoolean (*)(EGLDisplay, EGLint, EGLint, EGLuint64KHR *, EGLBoolean *, EGLint *);
using QueryDisplayAttrib = EGLBoolean (*)(EGLDisplay, EGLint, EGLAttrib *);
using QueryDeviceString = const char *(*)(void *, EGLint);

struct ParamsResult
{
    int state = 0; // 0 waiting, 1 made, -1 refused
    wl_buffer *buffer = nullptr;
};
void onCreated(void *d, zwp_linux_buffer_params_v1 *, wl_buffer *b)
{
    auto *r = static_cast<ParamsResult *>(d);
    r->buffer = b;
    r->state = 1;
}
void onFailed(void *d, zwp_linux_buffer_params_v1 *) { static_cast<ParamsResult *>(d)->state = -1; }
const zwp_linux_buffer_params_v1_listener paramsListener = { onCreated, onFailed };

} // namespace

void HdrBuffers::onRelease(void *data, wl_buffer *)
{
    static_cast<Buf *>(data)->busy = false;
}
static const wl_buffer_listener releaseListener = { [](void *d, wl_buffer *b) { HdrBuffers::onRelease(d, b); } };

HdrBuffers::HdrBuffers(void *eglDisplay, const QString &forced)
    : m_dpy(eglDisplay)
    , m_forced(forced)
{
}

HdrBuffers::~HdrBuffers()
{
    dropBuffers();
    if (m_gbm) gbm.deviceDestroy(m_gbm);
    if (m_drmFd >= 0) close(m_drmFd);
    if (m_dmabuf) wl_proxy_wrapper_destroy(m_dmabuf);
    if (m_shm) wl_proxy_wrapper_destroy(m_shm);
    if (m_queue) wl_event_queue_destroy(m_queue);
}

bool HdrBuffers::begin(QString *why, QString *notes)
{
    WlColor *wl = WlColor::get();
    if (!wl || !gl.load()) {
        *why = QStringLiteral("no GL functions");
        return false;
    }
    m_display = wl->display;
    m_queue = wl_display_create_queue(m_display);
    QString passed;
    if (m_forced != QLatin1String("shm")) {
        if (beginDmabuf(&passed)) return true;
        if (notes) *notes = QStringLiteral("no dmabuf: ") + passed;
    }
    if (m_forced != QLatin1String("dmabuf") && beginShm(why)) return true;
    if (m_forced == QLatin1String("dmabuf")) *why = QStringLiteral("no dmabuf: ") + passed;
    return false;
}

QString HdrBuffers::describe() const
{
    if (m_way == Way::None) return QStringLiteral("none");
    return QStringLiteral("%1 %2 (%3 bit)").arg(m_way == Way::Dmabuf ? QStringLiteral("dmabuf") : QStringLiteral("shm"), name(m_format)).arg(m_bits);
}

bool HdrBuffers::beginDmabuf(QString *why)
{
    WlColor *wl = WlColor::get();
    if (!wl->dmabuf || wl->dmabufFormats.isEmpty()) {
        *why = QStringLiteral("the compositor offers none");
        return false;
    }
    const char *ext = eglQueryString(m_dpy, EGL_EXTENSIONS);
    if (!ext || !std::strstr(ext, "EGL_EXT_image_dma_buf_import") || !gl.imageTargetTexture2D
        || !eglGetProcAddress("eglCreateImageKHR")) {
        *why = QStringLiteral("EGL can't take dmabufs");
        return false;
    }
    if (!gbm.load()) {
        *why = QStringLiteral("no libgbm");
        return false;
    }
    // The GPU EGL draws with (its render node), else the first one.
    QByteArray node;
    auto queryDisplay = reinterpret_cast<QueryDisplayAttrib>(eglGetProcAddress("eglQueryDisplayAttribEXT"));
    auto queryDevice = reinterpret_cast<QueryDeviceString>(eglGetProcAddress("eglQueryDeviceStringEXT"));
    EGLAttrib device = 0;
    if (queryDisplay && queryDevice && queryDisplay(m_dpy, EGL_DEVICE_EXT, &device) && device) {
        const char *render = queryDevice(reinterpret_cast<void *>(device), EGL_DRM_RENDER_NODE_FILE_EXT);
        if (!render) render = queryDevice(reinterpret_cast<void *>(device), EGL_DRM_DEVICE_FILE_EXT);
        if (render) node = render;
    }
    if (node.isEmpty()) node = "/dev/dri/renderD128";
    m_drmFd = open(node.constData(), O_RDWR | O_CLOEXEC);
    if (m_drmFd < 0) {
        *why = QStringLiteral("can't open %1").arg(QString::fromLatin1(node));
        return false;
    }
    m_gbm = gbm.createDevice(m_drmFd);
    if (!m_gbm) {
        *why = QStringLiteral("no GBM device on %1").arg(QString::fromLatin1(node));
        return false;
    }
    auto queryMods = std::strstr(ext, "EGL_EXT_image_dma_buf_import_modifiers")
        ? reinterpret_cast<QueryModifiers>(eglGetProcAddress("eglQueryDmaBufModifiersEXT")) : nullptr;
    // 10 bits first; a format with modifiers both sides know, else the
    // implicit layout where the compositor takes it.
    for (uint32_t f : {kXB30, kXR30, kXB24, kXR24}) {
        QList<uint64_t> theirs;
        for (const auto &[format, mod] : wl->dmabufFormats) {
            if (format == f) theirs << mod;
        }
        if (theirs.isEmpty()) continue;
        m_modCount = 0;
        if (queryMods && gbm.boCreateWithModifiers) {
            EGLuint64KHR mods[64];
            EGLBoolean external[64];
            EGLint n = 0;
            if (queryMods(m_dpy, EGLint(f), 64, mods, external, &n)) {
                for (EGLint i = 0; i < n && m_modCount < int(m_mods.size()); ++i) {
                    if (!external[i] && mods[i] != kModInvalid && theirs.contains(mods[i])) m_mods[size_t(m_modCount++)] = mods[i];
                }
            }
        }
        if (m_modCount == 0 && !theirs.contains(kModInvalid)) continue;
        // A small one first: whether GBM makes this kind at all.
        gbm_bo *probe = m_modCount > 0
            ? gbm.boCreateWithModifiers(m_gbm, 64, 64, f, m_mods.data(), unsigned(m_modCount))
            : gbm.boCreate(m_gbm, 64, 64, f, kGbmUseRendering);
        if (!probe) continue;
        gbm.boDestroy(probe);
        m_format = f;
        m_bits = tenBit(f) ? 10 : 8;
        m_way = Way::Dmabuf;
        // Buffers made from here on land on our queue.
        m_dmabuf = static_cast<zwp_linux_dmabuf_v1 *>(wl_proxy_create_wrapper(wl->dmabuf));
        wl_proxy_set_queue(reinterpret_cast<wl_proxy *>(m_dmabuf), m_queue);
        return true;
    }
    *why = QStringLiteral("no format both GBM and the compositor take (%1)").arg(QString::fromLatin1(node));
    return false;
}

bool HdrBuffers::beginShm(QString *why)
{
    WlColor *wl = WlColor::get();
    if (!wl->shm) {
        *why = QStringLiteral("no shared memory buffers");
        return false;
    }
    m_format = wl->shmFormats.contains(kXB30) ? kXB30 : wl->shmFormats.contains(kXR30) ? kXR30 : kShmXrgb8888;
    m_bits = tenBit(m_format) ? 10 : 8;
    m_way = Way::Shm;
    m_shm = static_cast<wl_shm *>(wl_proxy_create_wrapper(wl->shm));
    wl_proxy_set_queue(reinterpret_cast<wl_proxy *>(m_shm), m_queue);
    return true;
}

void HdrBuffers::dropBuffers()
{
    auto destroyImage = reinterpret_cast<DestroyImage>(eglGetProcAddress("eglDestroyImageKHR"));
    for (Buf &b : m_bufs) {
        if (b.buffer) wl_buffer_destroy(b.buffer);
        if (b.fbo) gl.deleteFramebuffers(1, &b.fbo);
        if (b.tex) gl.deleteTextures(1, &b.tex);
        if (b.image && destroyImage) destroyImage(m_dpy, b.image);
        if (b.bo) gbm.boDestroy(b.bo);
        if (b.data) munmap(b.data, b.size);
        b = Buf();
    }
    if (m_fbo) gl.deleteFramebuffers(1, &m_fbo);
    if (m_tex) gl.deleteTextures(1, &m_tex);
    m_fbo = m_tex = 0;
    m_current = nullptr;
    m_w = m_h = 0;
}

bool HdrBuffers::makeDmabuf(Buf &b, QString *why)
{
    b.bo = m_modCount > 0
        ? gbm.boCreateWithModifiers(m_gbm, uint32_t(m_w), uint32_t(m_h), m_format, m_mods.data(), unsigned(m_modCount))
        : gbm.boCreate(m_gbm, uint32_t(m_w), uint32_t(m_h), m_format, kGbmUseRendering);
    if (!b.bo) {
        *why = QStringLiteral("GBM made no %1x%2 buffer").arg(m_w).arg(m_h);
        return false;
    }
    const uint64_t mod = m_modCount > 0 ? gbm.boGetModifier(b.bo) : kModInvalid;
    const int planes = std::clamp(gbm.boGetPlaneCount(b.bo), 1, 4);
    m_modifier = mod;
    m_planes = planes;
    const int fd = gbm.boGetFd(b.bo);
    if (fd < 0) {
        *why = QStringLiteral("GBM gave no file for the buffer");
        return false;
    }
    // GL draws into it through an EGLImage ...
    static const EGLint planeKeys[4][5] = {
        {EGL_DMA_BUF_PLANE0_FD_EXT, EGL_DMA_BUF_PLANE0_OFFSET_EXT, EGL_DMA_BUF_PLANE0_PITCH_EXT, EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT},
        {EGL_DMA_BUF_PLANE1_FD_EXT, EGL_DMA_BUF_PLANE1_OFFSET_EXT, EGL_DMA_BUF_PLANE1_PITCH_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT},
        {EGL_DMA_BUF_PLANE2_FD_EXT, EGL_DMA_BUF_PLANE2_OFFSET_EXT, EGL_DMA_BUF_PLANE2_PITCH_EXT, EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT},
        {EGL_DMA_BUF_PLANE3_FD_EXT, EGL_DMA_BUF_PLANE3_OFFSET_EXT, EGL_DMA_BUF_PLANE3_PITCH_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT, EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT},
    };
    EGLint attrs[64];
    int n = 0;
    attrs[n++] = EGL_WIDTH;
    attrs[n++] = m_w;
    attrs[n++] = EGL_HEIGHT;
    attrs[n++] = m_h;
    attrs[n++] = EGL_LINUX_DRM_FOURCC_EXT;
    attrs[n++] = EGLint(m_format);
    for (int p = 0; p < planes; ++p) {
        attrs[n++] = planeKeys[p][0];
        attrs[n++] = fd;
        attrs[n++] = planeKeys[p][1];
        attrs[n++] = EGLint(gbm.boGetOffset(b.bo, p));
        attrs[n++] = planeKeys[p][2];
        attrs[n++] = EGLint(gbm.boGetStrideForPlane(b.bo, p));
        if (mod != kModInvalid) {
            attrs[n++] = planeKeys[p][3];
            attrs[n++] = EGLint(uint32_t(mod & 0xffffffffu));
            attrs[n++] = planeKeys[p][4];
            attrs[n++] = EGLint(uint32_t(mod >> 32));
        }
    }
    attrs[n++] = EGL_NONE;
    auto createImage = reinterpret_cast<CreateImage>(eglGetProcAddress("eglCreateImageKHR"));
    b.image = createImage(m_dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attrs);
    if (b.image == EGL_NO_IMAGE_KHR) {
        b.image = nullptr;
        close(fd);
        *why = QStringLiteral("EGL took no buffer (0x%1, modifier 0x%2)").arg(eglGetError(), 0, 16).arg(mod, 0, 16);
        return false;
    }
    gl.genTextures(1, &b.tex);
    gl.bindTexture(kGlTexture2d, b.tex);
    gl.texParameteri(kGlTexture2d, kGlTextureMinFilter, int(kGlNearest));
    gl.texParameteri(kGlTexture2d, kGlTextureMagFilter, int(kGlNearest));
    gl.imageTargetTexture2D(kGlTexture2d, b.image);
    gl.bindTexture(kGlTexture2d, 0);
    gl.genFramebuffers(1, &b.fbo);
    gl.bindFramebuffer(kGlFramebuffer, b.fbo);
    gl.framebufferTexture2D(kGlFramebuffer, kGlColorAttachment0, kGlTexture2d, b.tex, 0);
    const unsigned int status = gl.checkFramebufferStatus(kGlFramebuffer);
    gl.bindFramebuffer(kGlFramebuffer, 0);
    if (status != kGlFramebufferComplete) {
        close(fd);
        *why = QStringLiteral("GL can't draw into the buffer (0x%1)").arg(status, 0, 16);
        return false;
    }
    // ... and the compositor takes it as it is. Asked for and waited for
    // (never "create_immed": a refusal there would end the connection).
    auto *params = zwp_linux_dmabuf_v1_create_params(m_dmabuf);
    for (int p = 0; p < planes; ++p) {
        zwp_linux_buffer_params_v1_add(params, fd, uint32_t(p), gbm.boGetOffset(b.bo, p), gbm.boGetStrideForPlane(b.bo, p),
                                       uint32_t(mod >> 32), uint32_t(mod & 0xffffffffu));
    }
    ParamsResult result;
    zwp_linux_buffer_params_v1_add_listener(params, &paramsListener, &result);
    zwp_linux_buffer_params_v1_create(params, m_w, m_h, m_format, 0);
    close(fd); // sent (libwayland keeps its own copy until then)
    for (int i = 0; i < 4 && result.state == 0; ++i) {
        if (wl_display_roundtrip_queue(m_display, m_queue) < 0) break;
    }
    zwp_linux_buffer_params_v1_destroy(params);
    if (result.state != 1 || !result.buffer) {
        *why = QStringLiteral("the compositor refused the buffer (%1, modifier 0x%2)").arg(name(m_format)).arg(mod, 0, 16);
        return false;
    }
    b.buffer = result.buffer;
    wl_buffer_add_listener(b.buffer, &releaseListener, &b);
    return true;
}

bool HdrBuffers::makeShm(Buf &b, QString *why)
{
    const int stride = m_w * 4;
    b.size = size_t(stride) * size_t(m_h);
    const int fd = memfd_create("game-companion-hdr", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, off_t(b.size)) != 0) {
        if (fd >= 0) close(fd);
        b.size = 0;
        *why = QStringLiteral("no shared memory");
        return false;
    }
    b.data = mmap(nullptr, b.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (b.data == MAP_FAILED) {
        b.data = nullptr;
        b.size = 0;
        close(fd);
        *why = QStringLiteral("shared memory not mapped");
        return false;
    }
    wl_shm_pool *pool = wl_shm_create_pool(m_shm, fd, int32_t(b.size));
    b.buffer = wl_shm_pool_create_buffer(pool, 0, m_w, m_h, stride, m_format);
    wl_shm_pool_destroy(pool);
    close(fd);
    wl_buffer_add_listener(b.buffer, &releaseListener, &b);
    return true;
}

bool HdrBuffers::makeBuffers(QString *why)
{
    if (m_way == Way::Shm) {
        gl.genTextures(1, &m_tex);
        gl.bindTexture(kGlTexture2d, m_tex);
        gl.texParameteri(kGlTexture2d, kGlTextureMinFilter, int(kGlNearest));
        gl.texParameteri(kGlTexture2d, kGlTextureMagFilter, int(kGlNearest));
        const bool ten = m_bits == 10;
        gl.texImage2D(kGlTexture2d, 0, int(ten ? kGlRgb10A2 : kGlRgba8), m_w, m_h, 0, kGlRgba,
                      ten ? kGlUnsignedInt2101010Rev : kGlUnsignedByte, nullptr);
        gl.bindTexture(kGlTexture2d, 0);
        gl.genFramebuffers(1, &m_fbo);
        gl.bindFramebuffer(kGlFramebuffer, m_fbo);
        gl.framebufferTexture2D(kGlFramebuffer, kGlColorAttachment0, kGlTexture2d, m_tex, 0);
        const unsigned int status = gl.checkFramebufferStatus(kGlFramebuffer);
        gl.bindFramebuffer(kGlFramebuffer, 0);
        if (status != kGlFramebufferComplete) {
            *why = QStringLiteral("GL can't draw into a %1-bit texture (0x%2)").arg(m_bits).arg(status, 0, 16);
            return false;
        }
    }
    for (Buf &b : m_bufs) {
        if (!(m_way == Way::Dmabuf ? makeDmabuf(b, why) : makeShm(b, why))) return false;
    }
    return true;
}

HdrBuffers::Buf *HdrBuffers::takeFree()
{
    // The compositor gives a buffer back once it shows a newer one; a
    // moment's wait at most (never a hold: the frame is skipped).
    for (int tries = 0; tries < 8; ++tries) {
        wl_display_dispatch_queue_pending(m_display, m_queue);
        for (Buf &b : m_bufs) {
            if (b.buffer && !b.busy) return &b;
        }
        if (wl_display_prepare_read_queue(m_display, m_queue) != 0) continue;
        wl_display_flush(m_display);
        pollfd p{wl_display_get_fd(m_display), POLLIN, 0};
        if (poll(&p, 1, 2) > 0) {
            wl_display_read_events(m_display);
        } else {
            wl_display_cancel_read(m_display);
        }
    }
    return nullptr;
}

unsigned int HdrBuffers::target(int w, int h, int *internalFormat, QString *note)
{
    m_current = nullptr;
    m_error.clear();
    if (m_way == Way::None || w <= 0 || h <= 0) return 0;
    if (w != m_w || h != m_h) {
        dropBuffers();
        m_w = w;
        m_h = h;
        QString why;
        if (!makeBuffers(&why)) {
            dropBuffers();
            if (m_way == Way::Dmabuf && m_forced != QLatin1String("dmabuf")) {
                // dmabuf failed for real: shared memory from now on.
                if (note) *note = QStringLiteral("dmabuf failed (%1): shm instead").arg(why);
                if (gbm.lib && m_gbm) { gbm.deviceDestroy(m_gbm); m_gbm = nullptr; }
                if (m_drmFd >= 0) { close(m_drmFd); m_drmFd = -1; }
                if (m_dmabuf) { wl_proxy_wrapper_destroy(m_dmabuf); m_dmabuf = nullptr; }
                m_way = Way::None;
                QString shmWhy;
                if (!beginShm(&shmWhy)) {
                    m_error = why + QStringLiteral("; ") + shmWhy;
                    return 0;
                }
                return target(w, h, internalFormat, nullptr);
            }
            m_error = why;
            m_way = Way::None;
            return 0;
        }
        if (note && !m_noted) {
            m_noted = true;
            *note = m_way == Way::Dmabuf
                ? QStringLiteral("buffers: dmabuf %1, modifier 0x%2, %3 plane(s)").arg(name(m_format)).arg(m_modifier, 0, 16).arg(m_planes)
                : QStringLiteral("buffers: shm %1").arg(name(m_format));
        }
    }
    m_current = takeFree();
    if (!m_current) return 0;
    if (internalFormat) *internalFormat = int(m_bits == 10 ? kGlRgb10A2 : kGlRgba8);
    return m_way == Way::Dmabuf ? m_current->fbo : m_fbo;
}

void HdrBuffers::present(wl_surface *surface)
{
    Buf *b = m_current;
    m_current = nullptr;
    if (!b || !surface) return;
    if (m_way == Way::Dmabuf) {
        // Done drawing before the compositor reads it (NVIDIA has no
        // implicit sync): waits on this thread only.
        gl.finish();
    } else {
        // Top row first in both. XB30: R lowest, as GL's RGBA with
        // 2_10_10_10_REV; XR30: B lowest (BGRA); XR24: bytes B G R x.
        const unsigned int format = m_format == kXB30 ? kGlRgba : kGlBgra;
        const unsigned int type = m_bits == 10 ? kGlUnsignedInt2101010Rev : kGlUnsignedByte;
        gl.bindFramebuffer(kGlReadFramebuffer, m_fbo);
        gl.pixelStorei(kGlPackAlignment, 4);
        gl.readPixels(0, 0, m_w, m_h, format, type, b->data);
        gl.bindFramebuffer(kGlFramebuffer, 0);
    }
    b->busy = true;
    wl_surface_attach(surface, b->buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, INT32_MAX, INT32_MAX);
    wl_surface_commit(surface);
    wl_display_flush(m_display);
}
