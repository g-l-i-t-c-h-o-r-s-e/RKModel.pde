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
boolean previewUV = false;

// ---- GIF Recording Variables ----
GifMaker gifExport;
boolean recordRequested = false;
boolean isRecording = false;
int gifOutputWidth = 600;
int gifOutputHeight = 400;

String modelFolder = "models/";
String textureFolder = modelFolder;
String modelFile = "pony_type01_sunsetshimmer_lod1.rk";

int currentAnimationIndex = 1;
boolean loop = true;
String backgroundImage = "lol2.png";
int currentSet = 0;



//example of sequencing animations
int[] animOrder = {119, 120};  // The indices of the animations to play.
int animQueueIndex = 0;       // Which animation in the queue is next.
  void playit() {
    // Only proceed if not in transition AND no active animation
    if (!model.isInTransition() && (model.currentAnim == null || !model.currentAnim.playing)) {
      if (animQueueIndex < animOrder.length) {
        int animIndex = animOrder[animQueueIndex];
        if (animQueueIndex == 0) {
        model.playAnimation(model.animationNames.get(animIndex), false, 0, 29);
        }
        if (animQueueIndex == 1) {
        model.playAnimation(model.animationNames.get(animIndex), false, 10, 68);
        }
        println("Playing animation index: " + animIndex);
        animQueueIndex++;
      } else {
        animQueueIndex = 0;
        // Optional: Add delay before restarting sequence
        // delay(500); 
      }
    }
  }


  void setup() {
    size(1200, 800, P3D);
    
    // Enable drag-and-drop
    if (dragandrop) {
      setupDragAndDrop();
    }
      
    model = new RKModel(modelFolder + modelFile);
    String animFile = model.getAnimFile(modelFile); //detect anim
    model.loadAnimations(modelFolder + animFile);
    model.selectSet(14);
    
    //model.playAnimation("apple_idle_01_l",true,6,9);

    //if (model.animationNames.size() > 0) {
    //  model.playAnimation(model.animationNames.get(currentAnimationIndex), loop,0,0);
    //}
    
  
    // Set up PeasyCam
    cam = new PeasyCam(this, 130);
    
    backgroundImg = loadImage(backgroundImage);
    if (backgroundImg == null) {
      println("Error: background image not found");
    }
    
    if (previewUV) {
      // Initialize and launch the secondary window
      secWindow = new UV_Window();
      PApplet.runSketch(new String[] {"Secondary Window"}, secWindow);
    }
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
        playit();  // Check if animation finished, then trigger next


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
    
    if (keyCode == UP) {
      currentSet += 1;
      model.selectSet(currentSet);
      println("Animation index: " + currentAnimationIndex);
    } else if (keyCode == DOWN) {
      currentSet -= 1;
      model.selectSet(currentSet);
      println("Set index: " + currentSet);
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
