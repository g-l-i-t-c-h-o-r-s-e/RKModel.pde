import   peasy.*;
PeasyCam cam;
RKModel model;
PImage tex;

void setup() {
  size(1200, 800, P3D);
  tex = loadImage("3702524.jpg"); //still working on textures
  model = new RKModel("pony_type01_muffins_lod1.rk", tex);
  model.loadAnimations("pony_type01.anim");
  model.playAnimation("apple_idle_01_l");
  
  cam = new PeasyCam(this, 400);
}

void draw() {
  background(30);
  model.draw();
  model.drawBones();
  model.mesh.setStroke(color(255, 0, 0));
}
