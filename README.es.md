# NeatEditor

<p align="center">
  <img src="./docs/images/app-icon.png" width="128" height="128" alt="Icono de NeatEditor">
</p>

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-1f6feb)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green)](./LICENSE)

> Un editor de texto plano nativo para macOS.

**Idiomas:** [English](./README.md) | [简体中文](./README.zh-CN.md) | [日本語](./README.ja.md) | [한국어](./README.ko.md) | [Español](./README.es.md) | [Français](./README.fr.md) | [Deutsch](./README.de.md)

## Captura de pantalla

<p align="center">
  <img src="./docs/images/neateditor-main-window.png" alt="Captura de la ventana principal de NeatEditor" width="1120" />
</p>

## Instalación

**macOS 26.0+ · Apple silicon e Intel.** Solo macOS; no hay versión para Linux ni Windows.

```bash
brew install --cask x0c/tap/neateditor
```

O [descarga el DMG más reciente, firmado y notarizado](https://github.com/NeatMacApps/NeatEditor/releases/latest), ábrelo y arrastra `NeatEditor.app` a `Applications`.

Al abrirlo, usa `Command + O` para abrir un archivo o `Command + N` para un documento nuevo.

## Por qué NeatEditor

Para notas, borradores y cambios rápidos en archivos de texto.

## Características destacadas

- **Pestañas:** cambia, cierra, renombra en el sitio y vuelve a abrir la última pestaña cerrada.
- **Archivos locales:** abre desde Finder, arrastrando o pegando URLs de archivo; renombrar un documento guardado también cambia su nombre en disco.
- **Edición nativa:** números de línea, búsqueda, deshacer, composición IME y zoom de texto con `Command +/-`.
- **Guardado automático:** tras 2 segundos sin escribir, al cambiar de pestaña y cuando la app deja de estar activa. Las escrituras se ejecutan en orden.
- **Cambios externos:** gestiona los cambios de otro editor, script o agente de programación. Los búferes sin cambios se recargan; los cambios independientes se fusionan de forma conservadora; los conflictos detectados conservan ambas versiones.
- **Protección de contenido vacío:** el texto vacío o con solo espacios en blanco no sobrescribe un archivo existente. Vaciar el editor no vacía el archivo en disco.
- **Tu carpeta de documentos:** por defecto `~/Documents`; cámbiala en Ajustes → Editor → Carpeta de documentos. Los nuevos documentos se guardan en la carpeta elegida.
- **Siempre a la vista:** fija la ventana sobre otras y usa los menús y la barra de título nativos.

La protección de edición simultánea no impide que otros programas escriban en el archivo. Haz copias de seguridad de lo importante.

## Atajos principales

| Atajo | Acción |
| --- | --- |
| `Command + N` | Crea un documento nuevo. |
| `Command + T` | Abre otra pestaña nueva. |
| `Command + O` | Abre uno o varios archivos de texto locales. |
| `Command + S` | Guarda de inmediato la pestaña actual. |
| `Command + W` | Guarda y cierra la pestaña actual. |
| `Shift + Command + T` | Reabre la pestaña cerrada más recientemente. |
| `Command + F` | Muestra la barra de búsqueda integrada del editor actual. |
| `Command + =` o `Command + +` | Aumenta el zoom del texto del editor. |
| `Command + -` | Reduce el zoom del texto del editor. |
| `Command + ,` | Abre Ajustes. |
| `Shift + Return` | Inserta una línea nueva al final de la línea actual. |

<details>
<summary>Compilar desde el código fuente (Xcode)</summary>

Requiere macOS 26.0+, Xcode 26.0+ y [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.44+.

```bash
git clone https://github.com/NeatMacApps/NeatEditor.git
cd NeatEditor
xcodegen generate
open NeatEditor.xcodeproj
```

```bash
xcodebuild -project "NeatEditor.xcodeproj" \
  -scheme "NeatEditor" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  build
```

Consulta [CONTRIBUTING.md](CONTRIBUTING.md) para las pruebas y el desarrollo.

</details>

## Documentación

- [Contribuciones y pruebas](CONTRIBUTING.md)
- [Historial de versiones](CHANGELOG.md)

Las issues, sugerencias y pull requests son bienvenidas.

## Licencia

NeatEditor se distribuye bajo la [MIT License](LICENSE).

## Herramientas relacionadas

| Herramienta | Descripción |
|---|---|
| [NeatPaste](https://github.com/NeatMacApps/NeatPaste) | Historial del portapapeles de macOS en la barra de menús. |
| [NeatWebApp](https://github.com/NeatMacApps/NeatWebApp) | Convierte sitios web en apps de macOS con un lanzador en el notch. |
| [HandySwitch](https://github.com/x0c/HandySwitch) | Alterna el modo oscuro y evita el reposo desde la barra de menús. |
| [MacResourceMonitor](https://github.com/x0c/MacResourceMonitor) | Encuentra procesos que consumen CPU desde la barra de menús. |
| [Corral](https://github.com/corral-dev/corral) | Gestiona sesiones de agentes de programación en la terminal y continúa desde Mac o iPhone. |
