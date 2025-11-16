<div align="center">
  <img alt="logo" width="120" src="https://github.com/user-attachments/assets/f994edf4-c4be-46d2-a946-47d728171ffd" />
  <h1>Annotate</h1>
</div>

 <p align="center">
  <strong>A lightweight, keyboard-driven screen annotation tool for macOS that allows you to quickly draw, highlight, and annotate anything on your screen.</strong>
</p>

![annotate](https://github.com/user-attachments/assets/16baefb6-9fad-4702-9233-2991992ad030)

## ❓ Why?

Sometimes you need to emphasize a part of your screen or share ideas visually, and Annotate fills that gap with a simple, efficient interface. It enables real-time screen annotations using tools like pen, arrow, highlighter, rectangle, circle, counter, and text—perfect for highlighting and explaining concepts during presentations, live demos, or teaching sessions where visual annotations enhance understanding and clarity.

## ✨ Features

- 🎨 **Drawing Tools**:
  - ✒️ **Pen** tool for freehand drawing.
  - ➡️ **Arrow** tool for directional indicators.
  - 📏 **Line** tool for straight lines.
  - 🟨 **Highlighter** for emphasizing content.
  - 🔲 **Rectangle** shapes for boxing content.
  - ⭕ **Circle** shapes for highlighting areas.
  - 🔢 **Counter** tool for adding sequential numbered circles.
  - 📝 **Text** annotations with drag & edit support.
  - 👆 **Select** tool for moving and managing objects.
  - 🧹 **Eraser** tool for removing annotations.
- ✨ **Fade/Persist Mode:** Control whether annotations fade out after a duration or persist on the screen.
- 📌 **Always-On Mode:** Display annotations persistently without user interaction.
- 🌈 **Color Picker:** Easily select and persist your preferred color.
- ↕️ **Line Width Control:** Adjust line thickness with an interactive picker or Command+Scroll wheel.
- ⬛ **Board**: Toggle whiteboard or blackboard based on system appearance.
- 🖥️ **Fullscreen Support:** Works seamlessly over fullscreen applications.
- 🎛️ **Menu Bar Integration:** Quick access via a status icon.
- 🧹 **Auto-Clear Option:** Automatically clear all drawings when toggling the overlay.
- ⌨️ **Keyboard Shortcuts:** Switch between modes and toggle the overlay with customizable keyboard shortcuts.
- ⚡ **Global Hotkey:** Toggle Annotate with a global shortcut.
- 🔄 **Auto-Updates:** Automatic update checking with secure, cryptographically signed updates.

## 📦 Installation

### Download Release

1. **Download the Application:**

   - Go to [latest release](https://github.com/epilande/Annotate/releases/latest) page.
   - Download the `Annotate-x.x.x.dmg` file for easy installation, or `Annotate-x.x.x.zip` for manual installation.

2. **Install the Application:**

   **Using DMG (Recommended):**

   - Open the downloaded `Annotate-x.x.x.dmg` file.
   - Drag the `Annotate.app` into your **Applications** folder.

   **Using ZIP:**

   - Unzip the downloaded `Annotate-x.x.x.zip` file.
   - Drag the `Annotate.app` file into your **Applications** folder.

3. **Run the Application:**

   - Open your **Applications** folder and double-click `Annotate.app` to launch it.

> [!NOTE]
> Make sure your macOS version is 15 or later.
>
> The app is code-signed and notarized for macOS Gatekeeper compatibility.

### Build from Source

1. **Clone the Repository:**

   ```sh
   git clone https://github.com/epilande/Annotate
   ```

2. **Open the Project in Xcode:**

   ```sh
   cd Annotate
   open Annotate.xcodeproj
   ```

3. **Build and Run:**
   - Ensure you have the latest version of Xcode installed.
   - Select your target macOS version, then build and run the project in Xcode.

## 🚀 Quick Start

1. Launch Annotate.
2. Press the global hotkey (configurable in Settings) to toggle the overlay.
3. Start annotating with the default pen tool.
4. Press <kbd>Esc</kbd> to exit the overlay.

> [!TIP]
> The application provides a menu bar item that lets you select tools, choose colors, and perform actions like undo and redo.
> It also shows the application's active state, current color selection, tool, and mode.

<img width="250" alt="image" src="https://github.com/user-attachments/assets/40a94d67-29f1-49a6-9a3a-453d7f3d89e1" />

## 🎮 Usage

### Keyboard Shortcuts

> [!TIP]
> All tool shortcuts can be customized in Settings.

#### 🎨 Drawing Tools

| Key          | Tool            | Description                                         |
| ------------ | --------------- | --------------------------------------------------- |
| <kbd>P</kbd> | **Pen**         | Freehand drawing                                    |
| <kbd>L</kbd> | **Line**        | Draw straight lines                                 |
| <kbd>H</kbd> | **Highlighter** | Highlight areas with semi-transparent brush         |
| <kbd>R</kbd> | **Rectangle**   | Draw rectangles (hold <kbd>Option</kbd> for center) |
| <kbd>O</kbd> | **Circle**      | Draw circles (hold <kbd>Option</kbd> for center)    |
| <kbd>A</kbd> | **Arrow**       | Draw directional arrows                             |
| <kbd>N</kbd> | **Counter**     | Add sequential numbered circles (1, 2, 3...)        |
| <kbd>T</kbd> | **Text**        | Add text annotations                                |
| <kbd>E</kbd> | **Eraser**      | Remove annotations by dragging over them            |

#### 🎯 Tool Settings & Selection

| Key          | Tool             | Description                      |
| ------------ | ---------------- | -------------------------------- |
| <kbd>C</kbd> | **Color Picker** | Open color selection menu        |
| <kbd>W</kbd> | **Line Width**   | Open line width picker           |
| <kbd>V</kbd> | **Select**       | Select, move, and manage objects |
| <kbd>B</kbd> | **Board**        | Toggle whiteboard/blackboard     |

#### ⚡ Quick Actions

| Shortcut                                             | Action               | Description                                       |
| ---------------------------------------------------- | -------------------- | ------------------------------------------------- |
| <kbd>Space</kbd>                                     | **Toggle Fade Mode** | Switch between fade and persist modes             |
| <kbd>Delete</kbd>                                    | **Delete**           | Remove selected objects or most recent annotation |
| <kbd>Option</kbd> + <kbd>Delete</kbd>                | **Clear All**        | Remove all annotations                            |
| <kbd>Command</kbd> + <kbd>Z</kbd>                    | **Undo**             | Undo the last action                              |
| <kbd>Command</kbd> + <kbd>Shift</kbd> + <kbd>Z</kbd> | **Redo**             | Redo the last undone action                       |
| Mouse Backward Button                                | **Undo**             | Undo the last action (mouse button 3)             |
| Mouse Forward Button                                 | **Redo**             | Redo the last undone action (mouse button 4)      |
| <kbd>Command</kbd> + <kbd>Scroll</kbd>               | **Adjust Width**     | Quickly change line width                         |
| <kbd>Shift</kbd> (while drawing)                     | **Constrain**        | Lines: 45° angles; Pen/Highlighter: straight      |

#### 📋 Copy/Paste (Select Mode Only)

| Shortcut                          | Action         | Description                            |
| --------------------------------- | -------------- | -------------------------------------- |
| <kbd>Command</kbd> + <kbd>A</kbd> | **Select All** | Select all objects on the canvas       |
| <kbd>Command</kbd> + <kbd>C</kbd> | **Copy**       | Copy selected objects to clipboard     |
| <kbd>Command</kbd> + <kbd>X</kbd> | **Cut**        | Cut selected objects (copy + delete)   |
| <kbd>Command</kbd> + <kbd>V</kbd> | **Paste**      | Paste objects at mouse cursor position |
| <kbd>Command</kbd> + <kbd>D</kbd> | **Duplicate**  | Duplicate selected objects with offset |

#### 🪟 Overlay Controls

| Shortcut                                            | Action             | Description                          |
| --------------------------------------------------- | ------------------ | ------------------------------------ |
| Custom (Settings)                                   | **Toggle Overlay** | Show or hide the annotation overlay  |
| Custom (Settings)                                   | **Always-On Mode** | Persistent, non-interactive display  |
| <kbd>Esc</kbd> or <kbd>Command</kbd> + <kbd>W</kbd> | **Close**          | Closes the annotation overlay        |
| <kbd>Shift</kbd> + <kbd>Esc</kbd>                   | **Switch Mode**    | Close interactive → enable always-on |
| <kbd>Enter</kbd> or <kbd>Esc</kbd> (in text)        | **Finalize Text**  | Complete text input                  |

### Drawing Tools

#### Pen & Highlighter

- Click and drag to draw freehand lines
- Pen creates solid lines while highlighter creates semi-transparent, thicker strokes
- Hold <kbd>Shift</kbd> while drawing to constrain to a perfectly straight line at 45° angle increments (0°, 45°, 90°, 135°, 180°, 225°, 270°, 315°)
- Adjust line thickness using the Line Width Picker or <kbd>Command</kbd> + <kbd>Scroll</kbd> for quick adjustments

#### Line Width Control

Annotate provides flexible line width control:

- **Interactive Picker**: Press <kbd>W</kbd> or select "Line Width" from the menu bar to open a picker with:
  - Visual line preview showing the current thickness
  - Slider for precise width adjustment (0.5px to 20px)
  - Real-time feedback as you adjust
- **Quick Adjustment**: Hold <kbd>Command</kbd> and scroll your mouse wheel to quickly adjust line width
  - Scroll up to increase thickness
  - Scroll down to decrease thickness
  - Visual feedback appears at the bottom center showing current width and a preview line
- **Smart Scaling**: Arrowhead sizes automatically scale proportionally with line width for better visual balance

> [!TIP]
> Line width settings are persisted across sessions and apply to all drawing tools (pen, arrow, line, rectangle, circle).

#### Shapes (Rectangle, Circle)

- Click and drag to create shapes
- Hold <kbd>Option</kbd> while drawing rectangles or circles to expand from the center point

#### Arrow & Line

- Click and drag to create directional arrows or straight lines
- Hold <kbd>Shift</kbd> while drawing to snap to 45° angle increments for perfectly horizontal, vertical, or diagonal lines
- Arrows automatically create arrowheads pointing in the direction of the drag
- Lines create simple straight connections between two points

#### Text Annotations

- Click to place a text annotation
- Type your text and press <kbd>Enter</kbd> or <kbd>Esc</kbd> to finalize
- Double-click any text annotation to edit its content
- Click and drag to reposition text

#### Counter Tool

- Click anywhere to add sequential numbered circles (1, 2, 3...)
- Numbers increment automatically with each click

#### Select Tool

The Select tool allows you to manipulate existing annotations with precision:

- **Select Objects**: Press <kbd>V</kbd> to enter select mode

  - Click on objects to select them (lines, arrows, shapes, text, etc.)
  - Circles and rectangles must be clicked on their edges
  - A blue dashed bounding box appears around selected objects

- **Multiple Selection**:

  - **Rectangle Selection**: Click and drag on empty space to draw a selection rectangle
    - All objects inside or touching the rectangle are selected
  - **Shift+Click**: Hold <kbd>Shift</kbd> and click objects to add/remove them from selection
  - **Shift+Rectangle**: Hold <kbd>Shift</kbd> while drawing a rectangle to add to existing selection

- **Move Objects**:

  - Click anywhere inside the blue bounding box and drag to move selected objects
  - Multiple selected objects move together, maintaining their relative positions

- **Copy/Paste/Cut/Duplicate**:

  - **Select All** (<kbd>Command</kbd>+<kbd>A</kbd>): Select all objects on the canvas
  - **Copy** (<kbd>Command</kbd>+<kbd>C</kbd>): Copy selected objects to clipboard
  - **Cut** (<kbd>Command</kbd>+<kbd>X</kbd>): Cut selected objects (copy and delete)
  - **Paste** (<kbd>Command</kbd>+<kbd>V</kbd>): Paste objects at mouse cursor position
    - Automatically switches to select mode with pasted objects selected
  - **Duplicate** (<kbd>Command</kbd>+<kbd>D</kbd>): Duplicate selected objects with a small offset
    - Keeps you in select mode with duplicated objects selected

- **Delete Selected**:

  - Press <kbd>Delete</kbd> to remove all selected objects
  - Use <kbd>Command</kbd> + <kbd>Z</kbd> to undo deletions

- **Clear Selection**: Click on empty space (without <kbd>Shift</kbd>) to deselect all objects

> [!TIP]
> The select tool makes it easy to correct mistakes, reposition elements, and build complex diagrams by moving groups of objects together.

#### Eraser Tool

The Eraser tool allows you to remove specific annotations by dragging over them:

- **Activate Eraser**: Press <kbd>E</kbd> to enter eraser mode
- **Erase Annotations**: Click and drag over any annotation to remove it
  - Works with all annotation types (pen, arrows, lines, highlighters, shapes, text, counters)
  - Annotations are removed instantly as you drag over them
  - Supports undo (<kbd>Command</kbd> + <kbd>Z</kbd>) to restore erased items

### Drawing Modes

Toggle between modes with the <kbd>Space</kbd> key.

#### Fade Mode

In fade mode, annotations gradually disappear after a few seconds, keeping your screen clean while allowing for temporary emphasis.

#### Persist Mode

In persist mode, annotations remain on screen until manually cleared, allowing you to build up complex annotations over time.

### Always-On Mode

Always-On Mode displays your annotations persistently without any user interaction capability. This mode is ideal for presentations where you need important information visible without accidental modifications, reference displays with static guides or markers, and multi-screen setups where annotations remain on secondary monitors.

#### How to use:

1. Create your annotations in normal interactive mode
2. Toggle always-on mode via the global hotkey (configurable in Settings) or menu bar
3. Annotations become persistent and non-interactive
4. Use the same hotkey or menu option to exit always-on mode and resume editing

### Deletion Controls

- <kbd>Delete</kbd>: Removes the most recently added annotation.
- <kbd>Option</kbd> + <kbd>Delete</kbd>: Clear all annotations from the screen.

## ⚙️ Settings

Access the Settings panel from the menu bar icon or by pressing <kbd>Command</kbd> + <kbd>,</kbd>.

Settings are organized into two tabs: **General** and **Shortcuts**.

### General Settings

- **Activation Shortcut**: Set a global keyboard shortcut to toggle Annotate.
- **Always-On Mode**: Set a global keyboard shortcut to toggle always-on mode.
- **Clear Drawings on Toggle**: Automatically clear all drawings when activating Annotate.
- **Hide Tool Feedback**: Disable visual feedback when switching tools.
- **Show in Dock**: Display Annotate icon in the Dock.
- **Enable Board**: Show whiteboard or blackboard background.
- **Board Opacity**: Adjust board background transparency (10-100%).

### Keyboard Shortcuts

Customize keyboard shortcuts for all tools, organized into categories:

- **Drawing Tools**: Pen, Arrow, Line, Highlighter
- **Shapes**: Rectangle, Circle
- **Advanced Tools**: Counter, Text, Select
- **Utilities**: Color Picker, Line Width, Toggle Board

<img width="575" height="740" alt="image" src="https://github.com/user-attachments/assets/23909c0a-7d8f-4d36-8ea5-f6d5783e7d19" />

## 🔄 Auto-Updates

Annotate includes automatic update checking powered by [Sparkle](https://sparkle-project.org/):

- **Automatic Checks**: The app checks for updates once per day.
- **Manual Check**: Select **Check for Updates...** from the menu bar or use the About window.
- **Secure Updates**: All updates are cryptographically signed and verified before installation.

Updates are downloaded and installed seamlessly in the background. You'll be notified when a new version is available, with release notes and the option to install immediately or later.
