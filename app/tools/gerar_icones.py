"""Gera os ícones do app a partir do ícone "4_" da marca Coders4You (mesma geometria do C4Y Interview).

Uso: python app/tools/gerar_icones.py   (requer Pillow)
Saída:
  app/assets/brand/c4y_icon.png               logo usado dentro do app
  app/branding/android/res/...                ícone do Android (legado + adaptativo), notificação e abertura
O workflow "Gerar APK" copia app/branding/android/res para o projeto Android gerado.
"""

from pathlib import Path

from PIL import Image, ImageDraw

AZUL = "#0F1B2D"
LARANJA = "#EA580C"
BRANCO = "#FFFFFF"

CAIXA = 360
RAIO = 80
QUATRO = [(143, 121), (97, 188), (97, 218), (152, 218), (152, 243), (172, 243), (172, 172),
          (152, 172), (152, 201), (117, 201), (117, 192), (166, 121)]
TRACO = (191, 247, 270, 266)

APP = Path(__file__).resolve().parents[1]
RES = APP / "branding" / "android" / "res"
DENSIDADES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def desenhar(tamanho: int, fundo: bool = True, cor4=LARANJA, cor_traco=BRANCO, conteudo: float = 1.0) -> Image.Image:
    """`conteudo`: fração do lado ocupada pela caixa de 360 (o resto é margem transparente)."""
    escala = 4
    lado = tamanho * escala
    img = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = lado * (1 - conteudo) / 2
    k = (lado - 2 * m) / CAIXA
    t = lambda x, y: (m + x * k, m + y * k)  # noqa: E731
    if fundo:
        d.rounded_rectangle([m, m, lado - m - 1, lado - m - 1], radius=RAIO * k, fill=AZUL)
    d.polygon([t(x, y) for x, y in QUATRO], fill=cor4)
    x0, y0, x1, y1 = TRACO
    d.rectangle([*t(x0, y0), *t(x1, y1)], fill=cor_traco)
    return img.resize((tamanho, tamanho), Image.LANCZOS)


def salvar(img: Image.Image, caminho: Path) -> None:
    caminho.parent.mkdir(parents=True, exist_ok=True)
    img.save(caminho)


def main() -> None:
    salvar(desenhar(256), APP / "assets" / "brand" / "c4y_icon.png")
    for nome, f in DENSIDADES.items():
        # Ícone legado (Android < 8): quadrado arredondado azul com o "4_"
        salvar(desenhar(round(48 * f)), RES / f"mipmap-{nome}" / "ic_launcher.png")
        # Adaptativo: só o "4_" sobre fundo transparente, centralizado (a máscara do launcher mostra uns 72 de 108 dp)
        salvar(desenhar(round(108 * f), fundo=False, conteudo=84 / 108),  # um pouco maior que a área segura: o "4_" não chega às bordas
               RES / f"mipmap-{nome}" / "ic_launcher_foreground.png")
        # Notificação: silhueta branca (o Android pinta conforme o tema)
        salvar(desenhar(round(24 * f), fundo=False, cor4=BRANCO, conteudo=1.15),
               RES / f"drawable-{nome}" / "ic_notification.png")
    # Tela de abertura
    salvar(desenhar(288), RES / "drawable-nodpi" / "splash_logo.png")

    xml = {
        "mipmap-anydpi-v26/ic_launcher.xml": """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
""",
        "values/ic_launcher_background.xml": """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0F1B2D</color>
</resources>
""",
        "drawable/launch_background.xml": """<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/ic_launcher_background"/>
    <item><bitmap android:gravity="center" android:src="@drawable/splash_logo"/></item>
</layer-list>
""",
        # O encolhimento de recursos do build release apagaria o ícone de notificação (usado só por nome)
        "raw/keep.xml": """<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_notification,@drawable/splash_logo,@mipmap/ic_launcher_foreground"/>
""",
    }
    xml["drawable-v21/launch_background.xml"] = xml["drawable/launch_background.xml"]
    for rel, texto in xml.items():
        p = RES / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(texto, encoding="utf-8")
    print("Ícones gerados em", RES)


if __name__ == "__main__":
    main()
