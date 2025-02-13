import peasy.*;
import processing.opengl.*;
import gifAnimation.*;

import ddf.minim.*;
Minim minim;
AudioInput in;
AudioPlayer player;
AudioPlayer player2;
float audioSensitivity = 100.0;

boolean useMicrophone = false; //enable for microphone input instead

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
String modelFile = "pony_type01_muffins_lod1.rk";

int currentAnimationIndex = 119;
boolean loop = true;
String backgroundImage = "lol2.png";
int currentSet = 0;




//example of sequencing animations
int[] animOrder = {94, 94};  //{15, 15};  // The indices of the animations to play.
int animQueueIndex = 0;       // Which animation in the queue is next.
void playit() {
  // Only proceed if not in transition AND no active animation
  if (!model.isInTransition() && (model.currentAnim == null || !model.currentAnim.playing)) {
    if (animQueueIndex < animOrder.length) {
      int animIndex = animOrder[animQueueIndex];
      if (animQueueIndex == 0) {
        model.playAnimation(model.animationNames.get(animIndex), false, 0, 0);
      }
      if (animQueueIndex == 1) {
        model.playAnimation(model.animationNames.get(animIndex), false, 0, 0);
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

  minim = new Minim(this);
  if (useMicrophone) {
    in = minim.getLineIn(Minim.STEREO, 512);
  } else {
    // First audio file (vocals)
    player = minim.loadFile("vocal_track.wav");
    player.loop();  // Loop first file

    // Second audio file (optional)
    player2 = minim.loadFile("full_track_or_instrumental.wav");
    player2.loop();  // Loop second file
  }


  model = new RKModel(modelFolder + modelFile);
  model.enableMouthModulation(true);
  model.enableJawCorrection(1.0); //optional
  model.setMouthModulationSensitivity(audioSensitivity);
  model.setMouthModulationSmoothing(0.4);
  String animFile = model.getAnimFile(modelFile); //detect anim
  model.loadAnimations(modelFolder + animFile);
  //model.selectSet(14);

  //model.playAnimation("apple_idle_01_l",true,6,9);

  //if (model.animationNames.size() > 0) {
  //  model.playAnimation(model.animationNames.get(currentAnimationIndex), loop,0,0);
  //}


  // Set up PeasyCam
  cam = new PeasyCam(this, 130);
  //model.playAnimation(model.animationNames.get(15),loop,30,40);

  backgroundImg = loadImage(backgroundImage);
  if (backgroundImg == null) {
    println("Error: background image not found");
  }

  // Enable UV preview
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
  float amp = useMicrophone ? in.mix.level() : player.mix.level();
  model.setAmplitude(amp);
  model.drawBonesAnimated();
  
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
