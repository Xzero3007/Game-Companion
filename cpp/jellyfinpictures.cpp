#include "jellyfinpictures.h"

#include <QtCore/QByteArray>
#include <QtGui/QImage>
#include <QtQml/QQmlEngine>
#include <QtQuick/QQuickImageProvider>

#include <cstddef>
#include <cstdint>

extern "C" {
// src/jellyfin_object.rs
bool gc_jellyfin_picture(const uint8_t *id, size_t len, uint8_t **out, size_t *out_len);
void gc_jellyfin_picture_free(uint8_t *data, size_t len);
}

namespace {

class JellyfinPictures : public QQuickImageProvider
{
public:
    JellyfinPictures()
        // On Qt's picture threads: a slow server never holds up the overlay.
        : QQuickImageProvider(QQuickImageProvider::Image, QQmlImageProviderBase::ForceAsynchronousImageLoading)
    {
    }

    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override
    {
        const QByteArray key = id.toUtf8();
        uint8_t *data = nullptr;
        size_t len = 0;
        QImage image;
        if (gc_jellyfin_picture(reinterpret_cast<const uint8_t *>(key.constData()), static_cast<size_t>(key.size()), &data, &len)) {
            image.loadFromData(data, static_cast<int>(len));
            gc_jellyfin_picture_free(data, len);
        }
        if (!image.isNull() && requested.width() > 0 && image.width() > requested.width()) {
            image = image.scaledToWidth(requested.width(), Qt::SmoothTransformation);
        }
        if (size) {
            *size = image.size();
        }
        return image;
    }
};

} // namespace

void gc_register_jellyfin_pictures(QQmlEngine *engine)
{
    engine->addImageProvider(QStringLiteral("jellyfin"), new JellyfinPictures);
}
