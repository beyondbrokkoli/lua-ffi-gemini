### Windows 
If you have [LÖVE](https://love2d.org/) installed, you can launch the presentation without ever opening a terminal.  
Just follow these two steps for a perfect, click-and-play setup.

By default, Windows 11 applies display scaling that makes the engine's text look blurry.  
To force pixel-perfect, razor-sharp typography, you must override the OS:

1. Locate your installed LÖVE executable (usually at `C:\Program Files\LOVE\love.exe`).
2. Right-click `love.exe` and select **Properties**.
3. Go to the **Compatibility** tab.
4. Click **Change high DPI settings**.
5. Check the box at the bottom: **Override high DPI scaling behavior**.
6. Ensure the drop-down under "Scaling performed by:" is set to **Application**.
7. Click **OK** and **Apply**.

### Start
1. If you don't have one already, create a shortcut to `love.exe` on your Desktop.
2. Grab the **entire project folder** (the directory containing `main.lua` and the `sys_` modules).
3. **Drag and drop** that folder directly onto the LÖVE desktop shortcut.
