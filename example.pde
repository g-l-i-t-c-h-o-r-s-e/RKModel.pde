import peasy.*;
PeasyCam cam;
RKModel model;
PImage tex;

boolean showMesh = true; // Toggle for mesh visibility

void setup() {
  size(1200, 800, P3D);
  tex = loadImage("3702524.jpg"); //still working on textures
  model = new RKModel("pony_type01_muffins_lod1.rk", tex);
  //model.loadAnimations("pony_type01.anim");
  //model.playAnimation("apple_idle_01_l");
  
  cam = new PeasyCam(this, 400);
}

void draw() {
  background(30);
  
  // Draw mesh only if showMesh is true
  if (showMesh) {
    model.draw();
    model.mesh.setStroke(color(255, 0, 0));
  }
  
  // Always draw bones
  model.drawBones();
}

void keyPressed() {
  // Toggle mesh visibility when 'M' key is pressed
  if (key == 'm' || key == 'M') {
    showMesh = !showMesh;
    println("Mesh visibility toggled: " + showMesh);
  }
}
