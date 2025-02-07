import java.awt.*;
import java.awt.dnd.*;
import java.awt.datatransfer.*;
import java.io.File;
import java.util.List;
import javax.swing.*;

void setupDragAndDrop() {
  javax.swing.SwingUtilities.invokeLater(new Runnable() {
    public void run() {
      try {
        // Create a separate JFrame for drag-and-drop, this window will be the drop window
        JFrame dropFrame = new JFrame("Drop Area");
        dropFrame.setUndecorated(true);  // No window decorations
        dropFrame.setOpacity(0.3f);      // Semi-transparent for visual indication
        dropFrame.setSize(600, 400);     // Size of the drop window (adjust as needed)

        // Get screen size and calculate position for bottom-right corner
        Dimension screenSize = Toolkit.getDefaultToolkit().getScreenSize();
        int x = screenSize.width - dropFrame.getWidth();
        int y = screenSize.height - dropFrame.getHeight();
        dropFrame.setLocation(x, y);  // Set position to bottom-right corner

        dropFrame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);

        // Create a DropTarget to listen for file drops
        DropTarget dropTarget = new DropTarget(dropFrame, new DropTargetAdapter() {
          public void drop(DropTargetDropEvent evt) {
            try {
              evt.acceptDrop(DnDConstants.ACTION_COPY);
              Transferable transferable = evt.getTransferable();

              if (transferable.isDataFlavorSupported(DataFlavor.javaFileListFlavor)) {
                List<File> droppedFiles = (List<File>) transferable.getTransferData(DataFlavor.javaFileListFlavor);
                for (File file : droppedFiles) {
                  String filePath = file.getAbsolutePath();
                  PImage newBackground = loadImage(filePath);

                  if (newBackground != null) {
                    newBackground.resize(width, height);
                    backgroundImg = newBackground;
                    println("New background image loaded and resized.");
                  } else {
                    println("Error: Could not load the dropped image.");
                  }
                }
              }
            } catch (Exception ex) {
              ex.printStackTrace();
            }
          }
        });

        // Attach DropTarget to the new JFrame
        dropFrame.setDropTarget(dropTarget);
        dropFrame.setVisible(true);  // Make the drop window visible

      } catch (Exception e) {
        e.printStackTrace();
      }
    }
  });
}
