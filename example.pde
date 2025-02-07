import peasy.*;
import processing.opengl.*;
import gifAnimation.*;

PeasyCam cam;
RKModel model;
UV_Window secWindow;
PImage tex;
PImage backgroundImg;
boolean isPanningCamera = false;
boolean dragandrop = true; //drag and drop images into drop window to change background

int currentAnimationIndex = 324;
boolean loop = true;
String backgroundImage = "lol2.png";

// ---- GIF Recording Variables ----
GifMaker gifExport;
boolean recordRequested = false;
boolean isRecording = false;
int gifOutputWidth = 600;
int gifOutputHeight = 400;

String modelFolder = "models/";
String animFile = "pony_type01.anim";
String modelFile = "pony_type01_muffins_lod1.rk";
String textureFile = "pony_ponyville_162.png";

void setup() {
  size(1200, 800, P3D);
  
  // Enable drag-and-drop
  if (dragandrop) {
    setupDragAndDrop();
  }
  
  //tex = loadImage(modelFolder + model.materials.get(0)+".png"); //wip
  tex = loadImage(textureFile);
  model = new RKModel(modelFolder + modelFile, tex);
  model.loadAnimations(modelFolder + animFile);
  //model.playAnimation("apple_idle_01_l",true,6,9);
  model.playAnimation(model.animationNames.get(22), true, 30, 40);

  //if (model.animationNames.size() > 0) {
  //  model.playAnimation(model.animationNames.get(currentAnimationIndex), loop,0,0);
  //}
  

  // Set up PeasyCam
  cam = new PeasyCam(this, 130);
  
  backgroundImg = loadImage(backgroundImage);
  if (backgroundImg == null) {
    println("Error: background image not found");
  }
  
  // Initialize and launch the secondary window
  secWindow = new UV_Window();
  PApplet.runSketch(new String[] {"Secondary Window"}, secWindow);
}

void draw() {
  if (backgroundImg != null) {
    background(backgroundImg);
  } else {
    background(30); // fallback color
  }
  
  PGraphicsOpenGL pgl = (PGraphicsOpenGL) g;
  pgl.beginPGL();
    pgl.pgl.enable(PGL.CULL_FACE);
    pgl.pgl.frontFace(PGL.CW);
    pgl.pgl.cullFace(PGL.FRONT);
  
    pushMatrix();
      rotateY(PI * 0.8);
      translate(0, 30, 0);
      
      model.draw();
    popMatrix();
  pgl.endPGL();
  
  if (recordRequested && model.currentAnim != null) {
    if (model.currentAnim.currentFrame == model.currentAnim.currentStartFrame) {
      gifExport = new GifMaker(this, "recording.gif", 16);
      gifExport.setQuality(1);
      gifExport.setRepeat(0);
      isRecording = true;
      recordRequested = false;
      println("Started GIF recording...");
    }
  }

  if (isRecording && model.currentAnim != null) {
    PImage currentFrameImg = get();
    currentFrameImg.resize(gifOutputWidth, gifOutputHeight);
    gifExport.addFrame(currentFrameImg);

    int relativeFrame = model.currentAnim.currentFrame - model.currentAnim.currentStartFrame;
    int totalFrames = model.currentAnim.currentEndFrame - model.currentAnim.currentStartFrame + 1;
    println("Frame: " + relativeFrame + " of " + (totalFrames - 1));    

    if (model.currentAnim.currentFrame >= model.currentAnim.currentEndFrame) {
      gifExport.finish();
      isRecording = false;
      println("Finished GIF recording.");
    }
  }
  
}

void keyPressed() {
  if (model.animationNames.size() == 0) return;

  if (keyCode == RIGHT) {
    currentAnimationIndex = (currentAnimationIndex + 1) % model.animationNames.size();
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop, 0, 0);
    println("Animation index: " + currentAnimationIndex);
  } else if (keyCode == LEFT) {
    currentAnimationIndex = (currentAnimationIndex - 1 + model.animationNames.size()) % model.animationNames.size();
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop, 0, 0);
    println("Animation index: " + currentAnimationIndex);
  }
  
  if (key == 'r' || key == 'R') {
    if (!isRecording && !recordRequested) {
      recordRequested = true;
      println("Recording requested. Waiting for animation start...");
    }
  }
}

void mousePressed() {
  if (keyPressed && (key == CODED && keyCode == SHIFT)) {
    isPanningCamera = true;
    cam.setActive(false);
  }
}

void mouseDragged() {
  if (isPanningCamera) {
    float dx = mouseX - pmouseX;
    float dy = mouseY - pmouseY;
    cam.pan(-dx, -dy);
  }
}

void mouseReleased() {
  if (isPanningCamera) {
    isPanningCamera = false;
    cam.setActive(true);
  }
}
