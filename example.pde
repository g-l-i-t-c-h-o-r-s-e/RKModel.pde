import peasy.*;
import processing.opengl.*;
import com.hamoid.*;

import ddf.minim.*;
Minim minim;
AudioInput in;
AudioPlayer player;
AudioPlayer player2;

float audioSensitivity = 30.0; // Mouth modulation sensitivity (ranges between 50 and 150 depending on the model, 10 seems good for microphone input)
float smoothingFactor = 0.7; // Same case as above but (ranges between 0.4 and 0.8)
boolean useMicrophone = true; // Enable for microphone input instead

PeasyCam cam;
RKModel model;
UV_Window secWindow;
PImage tex;
PImage backgroundImg;
boolean isPanningCamera = false;
boolean dragandrop = true; //drag and drop images into drop window to change background
boolean previewUV = true;

// ---- Video Recording Variables ----
VideoExport videoExport;
boolean recordRequested = false;
boolean isRecording = false;
int captureStartFrame = -1;
int currentAnimFPS = 20;
String outputFormat = "gif"; // Change to "mp4" or "gif"
String outputVideoFile = "recording." + outputFormat;


String modelFolder = "models/";
String textureFolder = modelFolder;
String modelFile = "pony_type01_muffins_lod1.rk";

int currentAnimationIndex = 97;
boolean loop = true;
String backgroundImage = "lol2.png";
int currentSet = 0;



// Example of sequencing animations and recording it
int[] animOrder = {94, 92};        // The indices of the animations to play, add as many as you like.
int animQueueIndex = 0;            // Which animation in the queue is nex, don't touch.
boolean isSequencePlaying = false; // Boolean to track if we're in a sequence
void playit() {
  // Only proceed if not in transition AND no active animation
  if (!model.isInTransition() && (model.currentAnim == null || !model.currentAnim.playing)) {
    if (animQueueIndex < animOrder.length) {
      // Start recording at the beginning of the sequence
      if (animQueueIndex == 0) {
        recordRequested = true; // Request recording
        isSequencePlaying = true; // Mark that a sequence is playing
        println("Starting sequence and requesting recording...");
      }

      // Play the current animation in the sequence
      int animIndex = animOrder[animQueueIndex];
      model.playAnimation(model.animationNames.get(animIndex), false, 0, 0);
      println("Playing animation index: " + animIndex);
      animQueueIndex++;
    } else {
      // End of sequence
      if (isSequencePlaying) {
        isSequencePlaying = false; // Mark sequence as complete
        // animQueueIndex = 0; // Reset sequence index
        if (isRecording) {
          videoExport.endMovie(); // Stop recording
          isRecording = false;
          println("Finished sequence and stopped recording.");
        }
      }
    }
  }
}


void setup() {
  size(1200, 800, P3D);

  // Enable drag-and-drop background change
  if (dragandrop) {
    setupDragAndDrop();
  }

  // Setup audio objects for mouth/jaw modulation
  minim = new Minim(this);
  if (useMicrophone) {
    in = minim.getLineIn(Minim.STEREO, 512);
  } else {
    
    // First audio file (vocals)
    player = minim.loadFile("vocals.wav");
    player.loop();

    // Second audio file (optional background)
    player2 = minim.loadFile("background.wav");
    player2.loop();
  }

  // RK Model initilization and setup
  model = new RKModel(modelFolder + modelFile);
  //model.hideWings(true); //optional temporary hack to hide wings (for custom reskins)
  //model.enableMouthModulation(true); //optional mouth modulation via microphone or file input
  //model.enableJawCorrection(1.2); //additional optional function to close mouth a little more initially
  //model.setMouthModulationSensitivity(audioSensitivity);
  //model.setMouthModulationSmoothing(smoothingFactor);

  String animFile = model.getAnimFile(modelFile); //detect anim
  model.loadAnimations(modelFolder + animFile);
  //model.playAnimation(model.animationNames.get(currentAnimationIndex), loop,1,0); //skipping the first frame on a looped animation makes interpolation smoother
  //model.playAnimation("apple_idle_01_l",true,6,9);
  //model.selectSet(14); //select the models active body set if it has any

  // Set up PeasyCam
  cam = new PeasyCam(this, 130);
  backgroundImg = loadImage(backgroundImage);
  if (backgroundImg == null) {
    println("Error: background image not found");
  };

  // Enable UV preview
  if (previewUV) {
    secWindow = new UV_Window();
    PApplet.runSketch(new String[] {"Secondary Window"}, secWindow);
  }

  // VideoExport initialization
  videoExport = new VideoExport(this, (modelFile + "-" + millis() + "-" +  outputVideoFile));
  //videoExport.setDebugging(true);
  if(outputFormat.equals("gif")) {
    videoExport.setFfmpegVideoSettings(new String[]{
      "[ffmpeg]", "-y", "-f", "rawvideo", "-vcodec", "rawvideo",
      "-s", "[width]x[height]", "-pix_fmt", "rgb24", "-r", str(currentAnimFPS),
      "-i", "-", "-vf", "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse",
      "-loop", "0", "-vcodec", "gif", "[output]"
    });
  } else {
    videoExport.setFfmpegVideoSettings(new String[]{
      "[ffmpeg]", "-y", "-f", "rawvideo", "-vcodec", "rawvideo",
      "-s", "[width]x[height]", "-pix_fmt", "rgb24", "-r", str(currentAnimFPS),
      "-i", "-", "-an", "-vcodec", "h264",
      "-pix_fmt", "yuv420p", "-crf", "18", "[output]"
    });
    videoExport.setQuality(18, 128); // Higher quality for MP4
  }

//end of Setup() 
}

void draw() {
  if (backgroundImg != null) {
    background(backgroundImg);
  } else {
    background(30);
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
  //float amp = useMicrophone ? in.mix.level() : player.mix.level(); //get microphone or audio amplitude levels
  //model.setAmplitude(amp); //apply amplitude to models jaw/mouth bone
  //model.drawBonesAnimated();
  //model.drawBonesStatic();
    //playit();  // Function to play animation sequence

  popMatrix();
  pgl.endPGL();


  if (recordRequested && model.currentAnim != null) {
    if (model.currentAnim.currentFrame == model.currentAnim.currentStartFrame) {
      //currentAnimFPS = (int)model.currentAnim.clip.fps;
      videoExport.setFrameRate(currentAnimFPS);
      videoExport.startMovie();
      isRecording = true;
      recordRequested = false;
      model.currentAnim.clip.loop = false; //disable loop during recording I guess
      println("Started recording at " + currentAnimFPS + " FPS");
    }
  }

    // Use this if you are recording just one animation (triggered with R key)
  if (isRecording) {
    videoExport.saveFrame();
    if (!model.currentAnim.playing) {
      videoExport.endMovie();
      isRecording = false;
      model.currentAnim.playing = true; //restart animation
      model.currentAnim.clip.loop = true; //re-enable loop
      println("Finished video recording");
    }
  }

/*
  // Use this if you are recording an animation sequence
  if (isRecording) {
    videoExport.saveFrame();
  }
*/

//end of draw()
}

// Hotkey Functions
void keyPressed() {
  if (model.animationNames.size() == 0) return;

  if (keyCode == RIGHT) {
    currentAnimationIndex = (currentAnimationIndex + 1) % model.animationNames.size();
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop, 0, 0);
  } else if (keyCode == LEFT) {
    currentAnimationIndex = (currentAnimationIndex - 1 + model.animationNames.size()) % model.animationNames.size();
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop, 0, 0);
  }

  if (keyCode == UP) {
    currentSet += 1;
    model.selectSet(currentSet);
  } else if (keyCode == DOWN) {
    currentSet -= 1;
    model.selectSet(currentSet);
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
