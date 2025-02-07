import peasy.*;
import processing.opengl.*;
import gifAnimation.*;

PeasyCam cam;
RKModel model;
UV_Window secWindow;
PImage tex;
PImage backgroundImg;
boolean isPanningCamera = false;

int currentAnimationIndex = 1;
boolean loop = true;

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
  
  // Load texture and model
  //tex = loadImage(modelFolder + model.materials.get(0)+".png"); //wip
  tex = loadImage(textureFile);
  model = new RKModel(modelFolder + modelFile, tex);
  model.loadAnimations(modelFolder + animFile);
  //model.playAnimation("apple_idle_01_l",true,6,9);
  model.playAnimation(model.animationNames.get(324),true,27,43);


  //if (model.animationNames.size() > 0) {
  //  model.playAnimation(model.animationNames.get(currentAnimationIndex), loop,0,0);
  //}
  
  // Set up PeasyCam
  cam = new PeasyCam(this, 130);
  
  backgroundImg = loadImage("lol.png");
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
  
//println(model.currentAnim.currentStartFrame);
  PGraphicsOpenGL pgl = (PGraphicsOpenGL) g;
  pgl.beginPGL();
    pgl.pgl.enable(PGL.CULL_FACE);
    pgl.pgl.frontFace(PGL.CW);
    pgl.pgl.cullFace(PGL.FRONT);
  
    pushMatrix();
      rotateY(PI * 0.8);
      translate(0, 30, 0);
      
      model.draw();
      //model.drawBonesAnimated();
      //model.drawBonesStatic();
    popMatrix();
  pgl.endPGL();
  
  // When recording is requested, wait for the first frame of the animation (assumed to be 0) to start.
if (recordRequested && model.currentAnim != null) {
  // Start recording when the animation reaches the adjusted start frame
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

  // Calculate duration based on adjusted frames
  //int adjustedFrameDur = model.currentAnim.currentEndFrame - model.currentAnim.currentStartFrame + 1;

  // Stop when reaching the adjusted end frame
  if (model.currentAnim.currentFrame >= model.currentAnim.currentEndFrame) {
    gifExport.finish();
    isRecording = false;
    println("Finished GIF recording.");
  }
}
  
if (model.currentAnim != null) {
  int relativeFrame = model.currentAnim.currentFrame - model.currentAnim.currentStartFrame;
  int totalFrames = model.currentAnim.currentEndFrame - model.currentAnim.currentStartFrame + 1;
  println("Frame: " + relativeFrame + " of " + (totalFrames - 1));
}
}

void keyPressed() {
  if (model.animationNames.size() == 0) return;

  // Switch animations with the arrow keys.
  if (keyCode == RIGHT) {
    currentAnimationIndex = (currentAnimationIndex + 1) % model.animationNames.size();
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop,0,0);
    println("Animation index: " + currentAnimationIndex);
  } else if (keyCode == LEFT) {
    currentAnimationIndex = (currentAnimationIndex - 1 + model.animationNames.size()) % model.animationNames.size();
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop,0,0);
    println("Animation index: " + currentAnimationIndex);
  }
  
  // Start GIF recording when "R" is pressed.
  // Recording will actually start when the animation loops to its first frame.
  if (key == 'r' || key == 'R') {
    if (!isRecording && !recordRequested) {
      recordRequested = true;
      println("Recording requested. Waiting for animation start...");
    }
  }
}

void mousePressed() {
  if (keyPressed && (key == CODED && keyCode == SHIFT)) { // Check for Shift key
    isPanningCamera = true; // Enable camera panning
    cam.setActive(false); // Disable PeasyCam for panning
  }
}

void mouseDragged() {
  if (isPanningCamera) {
    // Calculate mouse movement delta
    float dx = mouseX - pmouseX;
    float dy = mouseY - pmouseY;
    // Pan the camera (negative values to match mouse movement direction)
    cam.pan(-dx, -dy);
  }
}

void mouseReleased() {
  if (isPanningCamera) {
    isPanningCamera = false; // Disable camera panning
    cam.setActive(true);  // Re-enable PeasyCam
  }
}


// ======================================================================
// Secondary Window for UV display
// ======================================================================
class UV_Window extends PApplet {
  PImage texture;
  ArrayList<PVector> uvs;
  ArrayList<int[]> triangles;

  public void settings() {
    // Use the model texture's dimensions for the secondary window.
    size(model.texture.width, model.texture.height - 50);
  }

  public void setup() {
    background(50);
    texture = model.texture;
    uvs = model.uvs;
    triangles = model.triangles;
  }

  public void draw() {
    background(50);

    // Draw the texture on a rectangle
    if (texture != null) {
      image(texture, 0, 0, width, height);
    }

    // Draw UV triangles and points over the texture
    if (uvs != null && triangles != null) {
      for (int[] tri : triangles) {
        PVector a = uvs.get(tri[0]);
        PVector b = uvs.get(tri[1]);
        PVector c = uvs.get(tri[2]);

        float ax = a.x * width, ay = a.y * height;
        float bx = b.x * width, by = b.y * height;
        float cx = c.x * width, cy = c.y * height;

        // Draw triangle outlines
        noFill();
        stroke(0, 255, 0);
        strokeWeight(1);
        triangle(ax, ay, bx, by, cx, cy);

        // Draw UV points as red dots
        fill(255, 0, 0);
        noStroke();
        ellipse(ax, ay, 5, 5);
        ellipse(bx, by, 5, 5);
        ellipse(cx, cy, 5, 5);
      }
    }
  }
}
