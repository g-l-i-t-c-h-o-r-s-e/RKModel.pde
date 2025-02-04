import peasy.*;
PeasyCam cam;
RKModel model;
import processing.opengl.*;
PImage tex;

int currentAnimationIndex = 1;
boolean loop = true;
UV_Window secWindow;

void setup() {
  size(1200, 800, P3D);
  tex = loadImage("pony_ponyville_162.png");
  model = new RKModel("pony_type01_muffins_lod1.rk", tex);
  model.loadAnimations("pony_type01.anim");
  //model.playAnimation("apple_idle_01_l", true);

  if (model.animationNames.size() > 0) {
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop);
  }

  cam = new PeasyCam(this, 130);

  // Initialize and launch the secondary window
  secWindow = new UV_Window();
  PApplet.runSketch(new String[] {"UV Map Window"}, secWindow);
}

void draw() {
  background(30);
  ((PGraphicsOpenGL)g).beginPGL(); // Access OpenGL context
  ((PGraphicsOpenGL)g).pgl.enable(PGL.CULL_FACE); // Enable face culling
  ((PGraphicsOpenGL)g).pgl.frontFace(PGL.CW); // Set clockwise winding as front face
  ((PGraphicsOpenGL)g).pgl.cullFace(PGL.FRONT); // Cull front faces

  // Some lighting for better shape visibility
  //ambientLight(128, 128, 128);
  //directionalLight(148, 128, 128, -1, 1, -1);
  //directionalLight(30, 30, 60, 1, -1, 0);

  pushMatrix();
  rotateY(PI * 0.8);
  translate(0, 30, 0);

  model.draw();
  model.drawBonesAnimated();
  //model.drawBonesStatic();
  
  popMatrix();
  ((PGraphicsOpenGL)g).endPGL();
}

void keyPressed() {
  if (model.animationNames.size() == 0) return;

  if (keyCode == RIGHT) {
    currentAnimationIndex = (currentAnimationIndex + 1) % model.animationNames.size();
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop);
    println(currentAnimationIndex);
  } else if (keyCode == LEFT) {
    currentAnimationIndex = (currentAnimationIndex - 1 + model.animationNames.size()) % model.animationNames.size();
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop);
    println(currentAnimationIndex);
  }
}

class UV_Window extends PApplet {
  PImage texture;
  ArrayList<PVector> uvs;
  ArrayList<int[]> triangles;

  public void settings() {
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

    // Draw UV triangles and points
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
