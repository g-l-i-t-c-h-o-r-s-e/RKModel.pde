// ======================================================================
// Secondary Window for UV display
// ======================================================================
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

    if (texture != null) {
      image(texture, 0, 0, width, height);
    }

    if (uvs != null && triangles != null) {
      for (int[] tri : triangles) {
        PVector a = uvs.get(tri[0]);
        PVector b = uvs.get(tri[1]);
        PVector c = uvs.get(tri[2]);

        float ax = a.x * width, ay = a.y * height;
        float bx = b.x * width, by = b.y * height;
        float cx = c.x * width, cy = c.y * height;

        noFill();
        stroke(0, 255, 0);
        strokeWeight(1);
        triangle(ax, ay, bx, by, cx, cy);

        fill(255, 0, 0);
        noStroke();
        ellipse(ax, ay, 5, 5);
        ellipse(bx, by, 5, 5);
        ellipse(cx, cy, 5, 5);
      }
    }
  }
}
