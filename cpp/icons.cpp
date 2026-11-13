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

QImage renderIcon(const QString &path, const QColor &colour, double line, bool filled, int w, int h)
{
    const QString rgb = colour.name(QColor::HexRgb);
    const QString opacity = QString::number(colour.alphaF(), 'f', 3);
    const QString svg = QStringLiteral(
        "<svg viewBox='0 0 24 24'>"
        "<path d='%1' fill='%2' fill-opacity='%3' stroke='%4' stroke-opacity='%5' stroke-width='%6' "
        "stroke-linecap='round' stroke-linejoin='round'/></svg>")
        .arg(path, filled ? rgb : QStringLiteral("none"), opacity, rgb, opacity, QString::number(line));
    QImage image(w, h, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QSvgRenderer renderer(svg.toUtf8());
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    renderer.render(&painter, QRectF(0, 0, w, h));
    painter.end();
    return image;
}

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
        const int w = requested.width() > 0 ? requested.width() : 24;
        const int h = requested.height() > 0 ? requested.height() : w;
        const QImage image = renderIcon(path, colour, line, filled, w, h);
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

rust::Vec<std::uint8_t> gc_tray_icon(std::int32_t size)
{
    // The bar's Games icon (a gamepad) in the accent gold, a little bolder
    // than in the bar so it stays clear at the panel's 16 to 24 px.
    static const QString gamepad = QStringLiteral(
        "M6 6h12a4 4 0 0 1 4 4v4a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4v-4a4 4 0 0 1 4-4z M6 12h4M8 10v4M15 11h.01M18 13h.01");
    rust::Vec<std::uint8_t> out;
    if (size <= 0 || size > 256) {
        return out;
    }
    const double line = size <= 24 ? 2.2 : 2.0;
    const QImage image = renderIcon(gamepad, QColor(0xe0, 0xa5, 0x26), line, false, size, size).convertToFormat(QImage::Format_ARGB32);
    out.reserve(std::size_t(size) * std::size_t(size) * 4);
    // ARGB32 in network byte order, row by row, as StatusNotifierItem wants.
    for (int y = 0; y < size; ++y) {
        const QRgb *row = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < size; ++x) {
            out.push_back(std::uint8_t(qAlpha(row[x])));
            out.push_back(std::uint8_t(qRed(row[x])));
            out.push_back(std::uint8_t(qGreen(row[x])));
            out.push_back(std::uint8_t(qBlue(row[x])));
        }
    }
    return out;
}
