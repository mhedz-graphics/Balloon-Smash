# Balloon Smash — MVP online

Juego multijugador 2D (2 jugadores) con estética pixel art: física de vuelo con globos
estilo *Balloon Fight* + combate de arena estilo *Smash Bros*.

- **Motor:** Godot 4.4 (GDScript).
- **Multijugador:** ENet de Godot con **servidor dedicado headless y autoritativo**
  (el servidor simula física, colisiones, daño y peligros; los clientes solo envían
  input y renderizan con interpolación).
- **Render:** 320×180 escalado a 1280×720, filtro nearest-neighbor.
- **Arte:** placeholders generados por código (`_draw()`), sin assets externos.

---

## Cómo ejecutar

Necesitas Godot 4.4.x o superior (probado con 4.4.1 y 4.7.2). Los comandos se ejecutan desde la carpeta del proyecto.
En Windows, `godot` es la ruta al ejecutable `Godot_v4.7.2-stable_win64.exe`.
Pulsar F5 en el editor abre un **cliente**; el servidor se arranca desde una terminal
aparte con el flag `--server`.

### Prueba rápida en Windows (recomendado)

En la carpeta del proyecto hay lanzadores que buscan Godot automáticamente:

| Archivo | Qué hace |
|---|---|
| `SERVIDOR.bat` | Abre el servidor headless. Es **una sola consola**; déjala abierta. |
| `CLIENTE.bat` | Abre **un** cliente (una ventana de juego). Ejecútalo otra vez para el segundo. |
| `PRUEBAS.bat` | Ejecuta las 27 pruebas automáticas de simulación. |
| `CERRAR.bat` | Cierra los clientes/servidor de este proyecto si se quedan abiertos. |

Prueba normal en una PC: abre `SERVIDOR.bat`, espera a que diga
“Esperando 2 jugadores…”, y ejecuta `CLIENTE.bat` **dos veces**.
Deberías tener exactamente **1 consola de servidor + 2 ventanas de juego**.

> En una misma PC solo la ventana con foco recibe el teclado. Para jugar de verdad
> entre 2 personas usa 2 PCs en la LAN; en una sola PC sirve para ver la conexión,
> el mapa y la sincronización (puedes alternar el foco entre ventanas).

### Servidor dedicado (headless) por consola

```bash
godot --headless --path . -- --server
```

Espera a 2 jugadores. El segundo cliente que entra inicia la partida.

Opcional: cambiar el puerto UDP (por defecto 7777).

```bash
godot --headless --path . -- --server --port=7777
```

### Clientes

```bash
godot --path .
```

Para conectarse a otra máquina de la LAN:

```bash
godot --path . -- --ip=192.168.1.50
```

> El servidor usa **UDP**. Para jugar por Internet hay que abrir/redirigir el puerto
> (7777 por defecto) en el router.
>
> En Windows, la primera vez que arranques el servidor aparecerá un aviso del Firewall:
> permite el acceso en redes privadas para jugar en LAN.

### Dos clientes en una sola máquina (prueba local)

Abre dos ventanas del proyecto (`godot --path .` dos veces) y conéctalas al servidor
local. Cada ventana controla a un jugador distinto. Recuerda que solo la ventana con
foco recibe el teclado; para una partida real entre 2 personas conviene usar 2 PCs.
Si se acumulan ventanas, ejecuta `CERRAR.bat`.

---

## Controles

Cada cliente controla a su propio personaje. Se aceptan los dos esquemas en cualquier
cliente:

| Acción | Jugador 1 | Jugador 2 |
|---|---|---|
| Mover izquierda / derecha | `A` / `D` | `←` / `→` |
| Aletear (impulso finito, cooldown 0,34 s) | `Espacio` (o `W`) | `Enter` / `Shift derecho` (o `↑`) |
| Ataque (pisotón / cuerpo a cuerpo) | `J` | `K` |
| Salir | `ESC` | `ESC` |

El ataque se ejecuta con cooldown de 0,55 s y se puede mantener pulsado.

---

## Reglas implementadas

- **2 globos:** flotación normal y altura máxima.
- **1 globo:** gravedad mayor (cae más rápido) y aleteo más débil.
- **0 globos:** el personaje cae y pierde la partida.
- **Pisotón:** si caes sobre un globo enemigo desde arriba y atacas, lo revientas.
- **Cuerpo a cuerpo:** aplica knockback horizontal; no revienta globos directamente.
- **Agua/abismo** en la parte inferior: al tocarla pierdes 1 globo y reapareces en tu
  spawn (si te quedan globos).
- **Rayo anti-camping:** si pasan 20 s sin que nadie pierda un globo, un rayo golpea a
  un jugador aleatorio vivo y le quita 1 globo.
- **Victoria:** reventar los 2 globos del rival.

---

## Mapa procedural

`game/map_gen.gd` genera la arena a partir de una semilla:

1. Plataforma de aterrizaje fija bajo cada spawn.
2. 6 plataformas flotantes aleatorias con separación mínima (AABB inflada) y zonas de
   spawn despejadas.
3. Garantiza al menos 2 plataformas cerca de cada spawn (además de la de aterrizaje).
4. Nubes decorativas.

El servidor elige la semilla al iniciar la partida y la envía a ambos clientes en
`receive_match_start`. Cliente y servidor generan exactamente el mismo mapa.

---

## Estructura del proyecto

```
Balloon Smash/
├── project.godot          # Config: resolución 320x180, stretch, filtro nearest
├── SERVIDOR.bat           # Lanzador del servidor headless (Windows)
├── CLIENTE.bat            # Lanzador de UN cliente (Windows)
├── PRUEBAS.bat            # Ejecuta las pruebas automáticas
├── CERRAR.bat             # Cierra clientes/servidor acumulados
├── game/
│   ├── game.tscn          # Escena única (lobby + partida + HUD)
│   ├── game.gd            # Red (RPCs), fases, lobby, input, interpolación y render
│   ├── match_sim.gd       # Simulación autoritativa: física, combate, agua, rayos
│   └── map_gen.gd         # Generación procedural determinista (semilla)
├── tests/
│   └── sim_test.gd        # Pruebas automáticas de mapa, vuelo, combate y rayos
└── README.md
```

### Flujo de red

```
Cliente A ──conecta──► Servidor (espera) ◄──conecta── Cliente B
                          │
                          ├─ elige semilla y simula la partida
                          ├─ receive_match_start(seed, p1, p2) ─► ambos clientes
                          ├─ receive_input(mx, flap, attack) ◄── clientes (60 Hz)
                          └─ receive_player_state(pid, pos, vel, globos...) ─► clientes
```

- El servidor es la única autoridad: posiciones, globos, colisiones y ganador.
- El cliente interpola entre las dos últimas instantáneas (`INTERP_TIME = 0,07 s`).
- Al perder un globo o recibir un rayo se muestra feedback visual local.
- La reconexión no está contemplada (fuera del MVP).

---

## Pruebas

Pruebas automáticas de la simulación (mapa determinista, vuelo, agua, pisotón,
cuerpo a cuerpo y rayo), sin red:

```bash
godot --headless --path . -s res://tests/sim_test.gd
```

Para pruebas de red automatizadas, los clientes aceptan `--quit-on-gameover`:

```bash
godot --headless --path . -- --quit-on-gameover
```

---

## Notas

- Todo el arte son rectángulos dibujados por código. Para sustituirlo por sprites PNG,
  reemplaza las llamadas de `_draw_character()` / `_draw_balloon()` / plataformas por
  `Sprite2D` y conserva las mismas posiciones y tamaños lógicos.
- El servidor headless también ejecuta la escena, pero no dibuja nada
  (`is_server` desactiva el render).
