import peasy.*;
PeasyCam cam;
RKModel model;
import processing.opengl.*;
PImage tex;

int currentAnimationIndex = 340;
boolean loop = true;

void setup() {
  size(1200, 800, P3D);
  tex = loadImage("pony_ponyville_162.png"); //still working on textures
  model = new RKModel("models/pony_type01_muffins_lod1.rk", tex);
  model.loadAnimations("models/pony_type01.anim");
  //model.playAnimation("apple_idle_01_l", true);
  
  if (model.animationNames.size() > 0) {
    model.playAnimation(model.animationNames.get(currentAnimationIndex), loop);
  }
  
  cam = new PeasyCam(this, 130);
}

void draw() {
  background(30);
  ((PGraphicsOpenGL)g).beginPGL(); // Access OpenGL context
  ((PGraphicsOpenGL)g).pgl.enable(PGL.CULL_FACE); // Enable face culling
  ((PGraphicsOpenGL)g).pgl.frontFace(PGL.CW); // Set clockwise winding as front face
  ((PGraphicsOpenGL)g).pgl.cullFace(PGL.FRONT); // Cull front faces

  // Some lighting for better shape visibility
  ambientLight(128, 128, 128);
  directionalLight(148, 128, 128, -1, 1, -1);
  directionalLight(30, 30, 60, 1, -1, 0);

  pushMatrix();
  rotateY(PI * 0.8);
  translate(0, 30, 0);

  //hint(DISABLE_DEPTH_TEST); // disable depth test to draw bones ontop of the model
  model.draw();

  //model.drawBonesStatic();
  model.drawBonesAnimated();
  
  popMatrix();
  //model.mesh.setStroke(color(255, 0, 0));
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
