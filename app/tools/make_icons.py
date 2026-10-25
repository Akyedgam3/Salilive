"""Builds the Android launcher icons from assets/logo.webp (run in CI before flutter_launcher_icons)."""
from PIL import Image

im = Image.open("assets/logo.webp").convert("RGBA")
navy = (11, 11, 26, 255)
s = im.crop((310, 140, 1000, 860))  # the "S" mark with the live dot


def place(size, scale, bg):
    canvas = Image.new("RGBA", (size, size), bg)
    k = size * scale / max(s.size)
    t = s.resize((int(s.width * k), int(s.height * k)), Image.LANCZOS)
    canvas.paste(t, ((size - t.width) // 2, (size - t.height) // 2), t)
    return canvas


place(1024, 0.78, navy).convert("RGB").save("assets/icon.png")
place(1024, 0.58, (0, 0, 0, 0)).save("assets/icon_fg.png")
print("icons ok")
