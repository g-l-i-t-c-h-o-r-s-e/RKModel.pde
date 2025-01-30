import peasy.*;
PeasyCam cam;
RKModel model;
PImage tex;

boolean showMesh = true; // Toggle for mesh visibility
boolean isManipulatingBone = false; // Track bone manipulation
boolean isPanningCamera = false; // Track camera panning

void setup() {
    size(1200, 800, P3D);
    tex = loadImage("3702524.jpg"); //still working on textures
    model = new RKModel("pony_type01_muffins_lod1.rk", tex);
    cam = new PeasyCam(this, 400);
    cam.setActive(true);
}

void draw() {
    background(30);
    rotateY(PI); // Apply a 180-degree rotation around the Y-axis in the renderer

    // Draw mesh only if showMesh is true
    if (showMesh) {
        model.draw();
        model.mesh.setStroke(color(255, 0, 0));
    }

    // Always draw bones
    model.drawBones();

    // Extract camera vectors, for moving bones with ctrl+click-drag
    PMatrix3D modelView = (PMatrix3D)getMatrix();
    model.cameraRight = new PVector(modelView.m00, modelView.m01, modelView.m02);
    model.cameraUp = new PVector(modelView.m10, modelView.m11, modelView.m12);
    model.cameraRight.normalize();
    model.cameraUp.normalize();
}

void keyPressed() {
    // Toggle mesh visibility when 'M' key is pressed
    if (key == 'm' || key == 'M') {
        showMesh = !showMesh;
        println("Mesh visibility toggled: " + showMesh);
    }
}

void mousePressed() {
    if (keyPressed && (key == CODED && keyCode == CONTROL)) { // Check for Ctrl key
        cam.setActive(false); // Disable PeasyCam
        if (model != null) {
            isManipulatingBone = model.selectBone(mouseX, mouseY);
            println(isManipulatingBone);
        }
    } else if (keyPressed && (key == CODED && keyCode == SHIFT)) { // Check for Shift key
        isPanningCamera = true; // Enable camera panning
        cam.setActive(false); // Disable PeasyCam for panning
    }
}

void mouseDragged() {
    if (isManipulatingBone && model != null) {
        model.dragBone(mouseX - pmouseX, mouseY - pmouseY);
    } else if (isPanningCamera) {
        // Calculate mouse movement delta
        float dx = mouseX - pmouseX;
        float dy = mouseY - pmouseY;
        // Pan the camera
        cam.pan(-dx, -dy); // Negative values to match mouse movement direction
    }
}

void mouseReleased() {
    if (isManipulatingBone && model != null) {
        model.selectedBone = null;
        cam.setActive(true); // Re-enable PeasyCam
        isManipulatingBone = false;
    } else if (isPanningCamera) {
        isPanningCamera = false; // Disable camera panning
        cam.setActive(true); // Re-enable PeasyCam
    }
}
