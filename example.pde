import   peasy.*;
PeasyCam cam;
RKModel model;
PImage tex;

void setup() {
  size(1200, 800, P3D);
  tex = loadImage("3702524.jpg"); //still working on textures
  // tex = loadImage("pony_ponyville_162.png"); //still working on textures
  model = new RKModel("pony_type01_muffins_lod1.rk", tex);
  model.loadAnimations("pony_type01.anim");
  model.playAnimation("apple_idle_01_l");
  
  cam = new PeasyCam(this, 130);
}

void draw() {
  background(30);
  
  // some lighting for better shape visibility
  ambientLight(128, 128, 128);
  directionalLight(148, 128, 128, -1, 1, -1);
  directionalLight(30, 30, 60, 1, -1, 0);
  
  pushMatrix();
  rotateY(PI * 0.8);
  translate(0,30,0);
  hint(ENABLE_DEPTH_TEST);
  model.draw();
  // disabling depth test to draw bones ontop of the model
  hint(DISABLE_DEPTH_TEST);
  // model.drawBonesStatic();
  model.drawBonesAnimated();
  popMatrix();
  model.mesh.setStroke(color(255, 0, 0));
}
