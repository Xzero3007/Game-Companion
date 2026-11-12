#include "icons.h"

#include <QtCore/QByteArray>
#include <QtCore/QUrl>
#include <QtGui/QColor>
#include <QtGui/QImage>
#include <QtGui/QPainter>
#include <QtQml/QQmlEngine>
#include <QtQuick/QQuickImageProvider>
#include <QtSvg/QSvgRenderer>

namespace {

class IconProvider : public QQuickImageProvider
{
public:
    IconProvider()
        : QQuickImageProvider(QQuickImageProvider::Image)
    {
    }

    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override
    {
        // <path>|<colour>|<line width>|<filled>; the path on a 24 px grid.
        const QStringList parts = QUrl::fromPercentEncoding(id.toUtf8()).split(QLatin1Char('|'));
        const QString path = parts.value(0);
        QColor colour(parts.value(1, QStringLiteral("#ffffff")));
        if (!colour.isValid()) {
            colour = Qt::white;
        }
        const double line = qBound(0.5, parts.value(2, QStringLiteral("1.8")).toDouble(), 4.0);
        const bool filled = parts.value(3) == QLatin1String("1");
        // Only path data: letters, digits, spaces, signs, dots and commas.
        for (const QChar c : path) {
            if (!(c.isLetterOrNumber() || c == QLatin1Char(' ') || c == QLatin1Char('-') || c == QLatin1Char('.') || c == QLatin1Char(','))) {
                return QImage();
            }
        }
        const QString rgb = colour.name(QColor::HexRgb);
        const QString opacity = QString::number(colour.alphaF(), 'f', 3);
        const QString svg = QStringLiteral(
            "<svg viewBox='0 0 24 24'>"
            "<path d='%1' fill='%2' fill-opacity='%3' stroke='%4' stroke-opacity='%5' stroke-width='%6' "
            "stroke-linecap='round' stroke-linejoin='round'/></svg>")
            .arg(path, filled ? rgb : QStringLiteral("none"), opacity, rgb, opacity, QString::number(line));
        const int w = requested.width() > 0 ? requested.width() : 24;
        const int h = requested.height() > 0 ? requested.height() : w;
        QImage image(w, h, QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);
        QSvgRenderer renderer(svg.toUtf8());
        QPainter painter(&image);
        painter.setRenderHint(QPainter::Antialiasing);
        renderer.render(&painter, QRectF(0, 0, w, h));
        painter.end();
        if (size) {
            *size = image.size();
        }
        return image;
    }
};

} // namespace

void gc_register_icons(QQmlEngine *engine)
{
    engine->addImageProvider(QStringLiteral("icon"), new IconProvider);
}
