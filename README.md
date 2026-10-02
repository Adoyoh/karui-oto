# Karui Oto — pickers MPD con fzf

Buscadores por teclado para MPD: canciones, artistas, álbumes y carpetas en
ventanas flotantes mínimas, con la elegida sonando al instante y el resto en
aleatorio.
Filosofía on-demand: **0 procesos en boot** — MPD arranca al primer pick y
`Mod+X` (o `kill`) lo baja todo. Esc sin nada sonando también apaga.

## Requisitos

| Obligatorio | Para qué | Notas |
|---|---|---|
| `mpd` | el daemon de música (tu config actual sirve) | probado 0.24 |
| `mpc` | CLI contra MPD | probado 0.24 |
| `fzf` | los pickers | reciente (~2024+; `install.sh` verifica `--accept-nth`) |
| `bash`, `coreutils`, `grep` | shuf/sort/awk de toda la vida | |
| `python3` (stdlib) | parsea `config.jsonc` (vendored, auditable) | duro desde v1.0 |
| `kitty` **o** `foot` | la ventana flotante (`terminal`) | paridad total de flags |

| Opcional | Para qué | Si falta |
|---|---|---|
| `mpdris2` | MPRIS (ver qué suena en tu barra) | `"mpris": false` |
| `playerctl` | teclas multimedia (`karui-media`) | solo afecta a eso |
| Nerd Font | iconos (lupa, puntero) | pon ascii en `icons` a mano |
| `mutagen` (python) | utilitario de retag puntual | no es runtime |

## Instalación (elige; ninguna toca tu `.bashrc`)

```sh
git clone https://github.com/Adoyoh/karui-oto.git && cd karui-oto
./install.sh --dry-run   # mira qué haría (recomendado: léeme antes)
./install.sh             # instala de verdad
```

1. Copia el árbol a `~/.local/share/karui-oto/` + symlinks en `~/.local/bin/`.
2. Crea `~/.config/karui-oto/config.jsonc` **solo si no existe** (jamás la pisa).
3. Imprime qué pegar en tu compositor (ver `binds/`: niri, hyprland).

Alternativas: clonar a `~/apps/` y usar rutas absolutas en los binds (cero
instalación), o symlink manual. Desinstalar: `./uninstall.sh [--purge] [comp]`
(también borra nuestros binds del compositor con backup; tus propios binds
quedan intactos).
Si `~/.local/bin` no está en tu `PATH`, te lo dice pero **lo agregas tú**.

## Atajos (`shortcuts` + `karui-oto binds`)

Los atajos viven en tu compositor, pero se **generan** desde la config:
el bloque `"shortcuts"` viene activo-vacío (sin asignar); pon tus combos
(`Mod+O`, `Mod+Shift+P`; string vacío = sin atajo) y corre:

```sh
karui-oto binds            # autodetecta niri|hyprland
karui-oto binds hyprland   # o explicita
karui-oto binds --copy     # al portapapeles (o avisa si no hay wl-copy/xclip)
```

No necesitas aplicarlos a mano: cada vez que abres un picker, karui-oto
sincroniza tus `shortcuts{}` con el compositor en segundo plano (backup +
bloque marcado, `--remove` lo quita). Edita el jsonc, guarda, y a la
siguiente pulsación ya funciona. `karui-oto binds --apply` sigue existiendo
para hacerlo a mano con confirmación.

Sin tocar archivos a mano, `setup` te ofrece aplicarlos al final, o directo:
`karui-oto binds --apply` (pide confirmación, backup + bloque marcado,
`--remove` lo quita). Cada compositor tiene su sintaxis — un ejemplo de
cada uno con el mismo atajo (`songs` = `Mod+O`):

```kdl
# niri (dentro de binds {}):
Mod+O hotkey-overlay-title="karui-oto: search song" { spawn "bash" "-c" "~/.local/bin/karui-oto songs"; }
```
```lua
-- hyprland.lua (>= 0.55, Lua; legacy hyprland.conf below for older).
-- Paths go absolute because Lua exec_cmd does not expand ~:
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("/home/tu-usuario/.local/bin/karui-oto songs"))
```
```ini
# hyprland.conf (legacy, < 0.55):
bind = $mainMod, O, exec, ~/.local/bin/karui-oto songs
```

Pega la salida en tu compositor. `binds/` trae ejemplos completos a mano.
Soportados: niri e hyprland (otros escritorios fueron recortados; el historial
git conserva sus traductores por si vuelven algún día).

## Configuración (`~/.config/karui-oto/config.jsonc`)

JSONC (JSON con `//` y `/* */`, como fastfetch). Todo comentado con defaults
en `config.jsonc.example`, en el mismo orden que el código. Lo esencial:

| Clave | Efecto |
|---|---|
| `terminal` = kitty\|foot | qué adaptador de `terminals/` abre el picker |
| `path`, `mpd_conf` | tu música y tu mpd (se expande `~`, se valida que existan) |
| `kitty` / `foot` (secciones) | config individual por terminal: `font`, `font_size`, `width`, `height`, `color`, `transparency` |
| `color` | `"#rrggbb"` = fondo + texto por contraste auto; `""` = default |
| `transparency` | 0.00–1.00 validado (kitty: solo fondo; foot: ventana entera, lava el texto si bajas de 1.0) |
| `font`, `font_size` | familia fontconfig (se avisa si no existe) + puntos |
| `theme` + sección `icons` | paleta (`themes/tuyo.sh`) y search/arrow/marker pegables |
| `shuffle`/`repeat` | `random`/`repeat` on/off (+ con/sin `shuf`) — global |
| `mpris` | mpDris2 diferido tras elegir (o nunca) — global |
| `modes` | overrides por bind: `songs`/`artists`/`albums`/`folders` con su propio `shuffle`/`repeat`/`mpris`; `""` = hereda el global |
| `logo` | logos del picker (kitty-only para imágenes): items `symbol` (texto/emoji en el header, con `color`/`size`/`position`) o `image` (logo de ventana kitty con `transparency`/`size`/posición de 9 puntos/`color`=tinte); `gif` no soportado, 1 imagen max, en foot las imágenes se ignoran |
| `hide` | array de regex fuera del modo artistas |

Clave desconocida = aviso (typo probable). Valor inválido = fatal con mensaje.

Overrides puntuales sin tocar el archivo (tests, aliases):
`KARUI_OTO_CONFIG=/ruta/otra.jsonc` (otra config) y
`KARUI_OTO_TERMINAL=foot` (otro terminal con tu config real).

## Shells y fuentes

Funciona **desde cualquier shell** (bash, zsh, fish, dash): los scripts
llevan shebang `#!/bin/bash` (siempre corren en bash) y los aliases son
POSIX. Nada que configurar por shell.

Las fuentes se buscan en la base fontconfig (`~/.fonts`,
`~/.local/share/fonts`, `/usr/share/fonts`, ...): pon tus `.ttf/.otf` ahí
y verifica con `fc-match "Nombre"`. Al arrancar, el programa avisa si tu
`font` no existe (y usa fallback); la default (Liberation Mono) se verifica
en `install.sh` solo como aviso, no como bloqueo.

## Convenciones de biblioteca

- **Artistas:** por tags `artist`+`albumartist` (vale cualquier layout:
  singles sueltos, una carpeta con todo). `X feat. Y` sale en X **y** en Y;
  `min_tracks` (default 1 = muestra todo; 2 oculta invitados de un solo tema). Tidy users:
  modo `folders`.
- **Canciones/álbumes:** por tags (`artist/album/title`; `%artist%` muestra el
  primer valor en tags múltiples). Álbumes ambiguos ("Greatest Hits") se
  desambiguan con artista (`find album+artist` exactos).
- **Carpetas:** cualquier subcarpeta tal cual (`Artista/[Año] Álbum` directo).

## Quirks conocidos (documentados, no bugs pendientes)

- `mpc playlist` imprime `Artista - Título`, **no paths**: jamás se ubica un
  tema con grep sobre playlist (ver `lib/picker.sh`).
- `mpc insert` agrega **al final** en mpd 0.24/mpc 0.24 (el man dice después
  de la actual): el código no depende de su posición.
- `mpc listall -f` **ignora** el formato: la lista con tags sale de
  `mpc search -f ... title ""` (matchea todo, ~0.3s en 5k temas).
- `mpc play` pelado con random on arranca al azar: siempre `play <N>`.
- Kitty tarda ~25s en abrir / diálogos GTK colgados en Hyprland o Niri:
  suele ser `xdg-desktop-portal-gnome` sin GNOME Shell (cuelga los
  portales Settings y FileChooser). No es fallo de karui-oto (`doctor`
  lo avisa): `sudo apt remove xdg-desktop-portal-gnome` (Nautilus
  sigue igual, usa libportal). Efecto medido: kitty 26.5s → ~1s.

## Roadmap

- [ ] Temas extra (latte claro, nord) + `background_image` pixel-art opcional
- [ ] Empaquetado real (AUR, .deb, home-manager) para no usar install.sh
- [ ] Modo géneros/listary por M3U

## Licencia

MIT — ver `LICENSE`. Edita el titular con tu nombre al forkear.
