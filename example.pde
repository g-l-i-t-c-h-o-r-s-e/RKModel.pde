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

void setup() {
  size(1200, 800, P3D);
  
  tex = loadImage("pony_ponyville_162.png"); // texture image
  model = new RKModel(modelFolder + "pony_type01_muffins_lod1.rk", tex);
  model.loadAnimations(modelFolder + "pony_type01.anim");

  if (model.animationNames.size() > 0) {
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop);
  }
  
  // Set up PeasyCam
  cam = new PeasyCam(this, 130);
  
  backgroundImg = loadImage("background.png");
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
      //model.drawBonesAnimated();
      //model.drawBonesStatic();
    popMatrix();
  pgl.endPGL();
  
  // When recording is requested, wait for the first frame of the animation (assumed to be 0) to start.
  if (recordRequested && (model.currentAnim.currentFrame - model.currentAnim.clip.startFrame) == 0) {
    // Create a new GifMaker with a frame delay of 16 ms (~60 FPS)
    gifExport = new GifMaker(this, "recording.gif", 16);
    gifExport.setQuality(1);  // Lower value means higher quality (1 is best quality)
    gifExport.setRepeat(0);  // Loop forever (or change to -1 for no looping)

    isRecording = true;
    recordRequested = false;
    println("Started GIF recording...");
  }
  
  // If recording, capture and add a scaled frame.
  if (isRecording) {
    // Capture the current canvas image...
    PImage currentFrameImg = get();
    // ...and resize it to the desired output GIF resolution.
    currentFrameImg.resize(gifOutputWidth, gifOutputHeight);
    gifExport.addFrame(currentFrameImg);
    
    // When we reach the last frame of the animation, finish the gif.
    if ((model.currentAnim.currentFrame - model.currentAnim.clip.startFrame) == model.frameDur - 1) {
      gifExport.finish();
      isRecording = false;
      println("Finished GIF recording.");
    }
  }
  
  // (Optional) Print out the current frame and total frames for debugging.
  // println("Frame: " + (model.currentAnim.currentFrame - model.currentAnim.clip.startFrame) + " of " + model.frameDur);
}

void keyPressed() {
  if (model.animationNames.size() == 0) return;

  // Switch animations with the arrow keys.
  if (keyCode == RIGHT) {
    currentAnimationIndex = (currentAnimationIndex + 1) % model.animationNames.size();
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop);
    println("Animation index: " + currentAnimationIndex);
  } else if (keyCode == LEFT) {
    currentAnimationIndex = (currentAnimationIndex - 1 + model.animationNames.size()) % model.animationNames.size();
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop);
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
