/*******************************************************************************
 * Animated MLP Gameloft RK Model Loader/Renderer for Processing 4 (WIP)
 * https://gist.github.com/g-l-i-t-c-h-o-r-s-e/5590148123825db0205a1ff0d0428f0e
 ********************************************************************************/

int readInt4(byte[] b, int o) {
  return (b[o] & 0xFF) | 
        ((b[o+1] & 0xFF) << 8) | 
        ((b[o+2] & 0xFF) << 16) | 
        ((b[o+3] & 0xFF) << 24);
}

float readFloat4(byte[] b, int o) {
  return Float.intBitsToFloat(readInt4(b, o));
}

short readShort2(byte[] b, int o) {
  return (short)((b[o] & 0xFF) | ((b[o+1] & 0xFF) << 8));
}

class RKHeader {
  String magic;
  int versionMajor;
  int versionMinor;
  String name;

  RKHeader(byte[] data) {
    try {
      magic = "";
      for(int i = 0; i < 8; i++) magic += char(data[i]);
      versionMajor = readInt4(data, 8);
      versionMinor = readInt4(data, 12);
      name = readString(data, 16, 64);
    } catch (Exception e) {
      println("Header Error: "+e);
    }
  }
  
  String readString(byte[] data, int o, int maxLen) {
    String s = "";
    for(int i=0; i<maxLen; i++) {
      if(data[o+i] == 0) break;
      s += char(data[o+i]);
    }
    return s.trim();
  }
}

class Section {
  int tag, offset, count, byteLength;
  Section(int tag, int offset, int count, int byteLength) {
    this.tag = tag;
    this.offset = offset;
    this.count = count;
    this.byteLength = byteLength;
  }
}

class Bone {
  int id;
  int parent;
  String name;
  PMatrix3D matrix;
  PMatrix3D inverseBindMatrix;
  PMatrix3D globalTransform;
  ArrayList<Bone> children = new ArrayList<>();

  Bone(int id, int parent, String name) {
    this.id = id;
    this.parent = parent;
    this.name = name;
    this.matrix = new PMatrix3D();
    this.inverseBindMatrix = new PMatrix3D();
    this.globalTransform = new PMatrix3D();
  }
}

class SkinningData {
  ArrayList<ArrayList<VertexWeight>> weights = new ArrayList<>();
}

class VertexWeight {
  int boneIndex;
  float weight;
  VertexWeight(int bi, float w) {
    boneIndex = bi;
    weight = w;
  }
}

class RKModel {
  RKHeader header;
  HashMap<Integer, Section> sections = new HashMap<>();
  ArrayList<PVector> vertices = new ArrayList<>();
  ArrayList<PVector> uvs = new ArrayList<>();
  ArrayList<int[]> triangles = new ArrayList<>();
  ArrayList<Bone> bones = new ArrayList<>();
  ArrayList<Bone> processingOrder;
  ArrayList<Bone> rootBones;
  HashMap<Integer, Integer> boneIdMap;
  ArrayList<String> materials = new ArrayList<>();
  SkinningData skinning = new SkinningData();
  PShape mesh;
  PImage texture;
  ArrayList<PVector> skinnedVerts = new ArrayList<>();

  RKModel(String filename, PImage tex) {
    byte[] data = loadBytes(filename);
    texture = tex;
    header = new RKHeader(data);
    
    if (!header.magic.equals("RKFORMAT")) return;
    
    loadSections(data);
    loadMaterials(data);
    loadBones(data);
    loadGeometry(data);
    computeInverseBindMatrices();
    buildMesh();
    applySkinning();
    printSummary();
  }

  void loadSections(byte[] data) {
    int offset = 80;
    for(int i=0; i<17; i++) {
      sections.put(readInt4(data, offset), new Section(
        readInt4(data, offset),
        readInt4(data, offset+4),
        readInt4(data, offset+8),
        readInt4(data, offset+12)
      ));
      offset += 16;
    }
  }

  void loadMaterials(byte[] data) {
    Section matSec = sections.get(2);
    if(matSec == null) return;
    
    int matSize = 320;
    for(int i=0; i<matSec.count; i++) {
      int off = matSec.offset + i*matSize;
      materials.add(header.readString(data, off, 64));
    }
  }

void loadBones(byte[] data) {
    Section boneSec = sections.get(7);
    if (boneSec == null) return;

    this.boneIdMap = new HashMap<>();
    int boneSize = 140;

    //rotate matrix 90 degrees around Z-axis + DOWNSCALE X-axis to 0.1?! OK THEN
    PMatrix3D axisCorrection = new PMatrix3D(
        0, -1, 0, 0,
        1, 0, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    );
    axisCorrection.scale(0.1, 0.1, 0.1); // Scale X-axis by 0.5

    for (int i = 0; i < boneSec.count; i++) {
        int off = boneSec.offset + i * boneSize;
        int parentId = readInt4(data, off);
        parentId = parentId == 0xFFFFFFFF ? -1 : parentId;

        int id = readInt4(data, off + 4);
        float[] matrixData = new float[16];
        for (int j = 0; j < 16; j++) {
            matrixData[j] = readFloat4(data, off + 12 + j * 4);
        }

        PMatrix3D mat = new PMatrix3D(
            matrixData[0], matrixData[1], matrixData[2], matrixData[3],
            matrixData[4], matrixData[5], matrixData[6], matrixData[7],
            matrixData[8], matrixData[9], matrixData[10], matrixData[11],
            matrixData[12], matrixData[13], matrixData[14], matrixData[15]
        );

        mat.preApply(axisCorrection);

        String name = header.readString(data, off + 76, 64);
        Bone bone = new Bone(id, parentId, name);
        bone.matrix = mat;
        bones.add(bone);
        boneIdMap.put(id, i);

        // Debug print to verify parent-child relationships
        println("Bone ID: " + id + ", Parent ID: " + parentId + ", Name: " + name);
    }
}

void computeInverseBindMatrices() {
    processingOrder = new ArrayList<>();
    rootBones = new ArrayList<>();
    
    for (Bone bone : bones) {
        if (bone.parent == -1) {
            rootBones.add(bone);
        }
    }
    
    for (Bone root : rootBones) {
        processingOrder.add(root);
        addChildrenRecursive(root, processingOrder);
    }
    
    for (Bone bone : processingOrder) {
        if (bone.parent == -1) {
            bone.globalTransform = bone.matrix.get();
        } else {
            Integer parentIndex = boneIdMap.get(bone.parent);
            if (parentIndex != null && parentIndex < bones.size()) {
                Bone parent = bones.get(parentIndex);
                bone.globalTransform = parent.globalTransform.get();
                bone.globalTransform.apply(bone.matrix);
            }
        }
        
        // Debug print
        println("Bone: " + bone.name);
        println("Local Matrix:");
        printMatrix(bone.matrix);
        println("Global Matrix:");
        printMatrix(bone.globalTransform);
        
        bone.inverseBindMatrix = bone.globalTransform.get();
        bone.inverseBindMatrix.invert();
    }
}

void printMatrix(PMatrix3D matrix) {
    float[] m = new float[16];
    matrix.get(m);
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            print(m[i * 4 + j] + " ");
        }
        println();
    }
}

  void addChildrenRecursive(Bone parent, ArrayList<Bone> processingOrder) {
    for (Bone bone : bones) {
        if (bone.parent == parent.id) {
            processingOrder.add(bone);
            addChildrenRecursive(bone, processingOrder);
        }
    }
  }

  void loadGeometry(byte[] data) {
    Section vertSec = sections.get(3);
    if(vertSec == null) return;
    
    int stride = vertSec.byteLength/vertSec.count;
    
    for(int i=0; i<vertSec.count; i++) {
      int off = vertSec.offset + i*stride;
      
      PVector pos = new PVector(
          readFloat4(data, off),
          readFloat4(data, off + 4),
          readFloat4(data, off + 8)
      );
      
      PVector uv = new PVector(0, 0);
      if(stride >= 16) {
        if(stride == 16 || stride == 20) {
          short u = readShort2(data, off+16);
          short v = readShort2(data, off+18);
          uv.x = map(u, -32767, 32767, 0, 1);
          uv.y = map(v, -32767, 32767, 1, 0);
        } 
        else if(stride == 28) {
          uv.x = readFloat4(data, off+16);
          uv.y = 1.0 - readFloat4(data, off+20);
        }
      }
      
      vertices.add(pos);
      uvs.add(uv);
    }

    Section faceSec = sections.get(4);
    if(faceSec == null) return;
    
    boolean use32bit = vertices.size() > 65535;
    int indexSize = use32bit ? 4 : 2;
    int triCount = faceSec.byteLength / (indexSize * 3);
    
    for(int i=0; i<triCount; i++) {
      int off = faceSec.offset + i * indexSize * 3;
      int[] tri = new int[3];
      
      for(int j=0; j<3; j++) {
        if(use32bit) {
          tri[j] = readInt4(data, off + (j*4));
        } else {
          tri[j] = readShort2(data, off + (j*2)) & 0xFFFF;
        }
      }
      triangles.add(tri);
    }
      
    Section weightSec = sections.get(17);
    if (weightSec != null) {
        int weightSize = weightSec.byteLength / weightSec.count;
        for (int i = 0; i < weightSec.count; i++) {
            int off = weightSec.offset + i * weightSize;
            ArrayList<VertexWeight> vWeights = new ArrayList<>();

            float totalWeight = 0;
            for (int j = 0; j < 4; j++) {
                int boneId = data[off + j] & 0xFF;
                Integer boneIndex = this.boneIdMap.get(boneId);

                if (boneIndex == null) continue;

                int weightOffset = off + 4 + (j * 2);
                int weightValue = readShort2(data, weightOffset) & 0xFFFF;
                float weight = weightValue / 65535.0f;

                if (weight > 0) {
                    vWeights.add(new VertexWeight(boneIndex, weight));
                    totalWeight += weight;
                }
            }

            if (totalWeight > 0) {
                for (VertexWeight w : vWeights) {
                    w.weight /= totalWeight;
                }
            }

            skinning.weights.add(vWeights);
        }
    } else {
        for (int i = 0; i < vertices.size(); i++) {
            skinning.weights.add(new ArrayList<VertexWeight>());
        }
    }
  }

  void buildMesh() {
    mesh = createShape();
    mesh.beginShape(TRIANGLES);
    mesh.texture(texture);
    mesh.textureMode(NORMAL);
    mesh.noStroke();
    
    for(int[] tri : triangles) {
      for(int i=0; i<3; i++) {
        PVector v = vertices.get(tri[i]);
        PVector uv = uvs.get(tri[i]);
        mesh.vertex(v.x, v.y, v.z, uv.x, uv.y);
      }
    }
    
    mesh.endShape();
    skinnedVerts = new ArrayList<>(vertices);
  }

  void applySkinning() {
    for (int i = 0; i < vertices.size(); i++) {
        PVector original = vertices.get(i);
        PVector skinned = new PVector();
        ArrayList<VertexWeight> weights = skinning.weights.get(i);
        float totalWeight = 0;

        for (VertexWeight w : weights) {
            if (w.boneIndex >= bones.size()) continue;
            Bone bone = bones.get(w.boneIndex);

            PMatrix3D skinningMatrix = new PMatrix3D();
            skinningMatrix.apply(bone.inverseBindMatrix);
            skinningMatrix.apply(bone.globalTransform);  

            PVector transformed = new PVector();
            skinningMatrix.mult(original, transformed);
            transformed.mult(w.weight);
            skinned.add(transformed);
            totalWeight += w.weight;
        }

        if (totalWeight > 0.001) {
            skinned.mult(1.0 / totalWeight);
        } else {
            skinned = original.copy();
        }

        skinnedVerts.set(i, skinned);
    }
    updateMeshVertices();
  }
  
  void updateMeshVertices() {
      int vertexIndex = 0;
      for (int[] tri : triangles) {
          for (int j = 0; j < 3; j++) {
              int originalIndex = tri[j];
              if (originalIndex < skinnedVerts.size()) {
                  PVector v = skinnedVerts.get(originalIndex);
                  mesh.setVertex(vertexIndex, v.x, v.y, v.z);
              }
              vertexIndex++;
          }
      }
  }
  
  void printSummary() {
    println("Model Summary:");
    println("Vertices: " + vertices.size());
    println("Triangles: " + triangles.size());
    println("Bones: " + bones.size());
  }

void drawBones() {
    // Track closest bone under mouse
    Bone hoveredBone = null;
    float closestDistance = Float.MAX_VALUE;
    
    // First pass: Calculate screen positions and find closest
    ArrayList<PVector> boneScreenPositions = new ArrayList<>();
    for (Bone bone : bones) {
        float[] m = new float[16];
        bone.globalTransform.get(m);
        float x = m[12];
        float y = m[13];
        float z = m[14];

        // Get screen position
        PVector screenPos = new PVector(
            screenX(x, y, z),
            screenY(x, y, z),
            screenZ(x, y, z)
        );
        boneScreenPositions.add(screenPos);

        // Skip bones behind camera
        if (screenPos.z <= 0) continue;

        // Calculate 2D distance to mouse
        float distToMouse = dist(mouseX, mouseY, screenPos.x, screenPos.y);
        
        // Track closest bone within threshold
        if (distToMouse < 10 && distToMouse < closestDistance) {
            closestDistance = distToMouse;
            hoveredBone = bone;
        }

        // Draw bone visuals (unchanged)
        pushMatrix();
        translate(x, y, z);
        sphere(2);
        popMatrix();

        if (bone.parent != -1) {
            Bone parent = bones.get(boneIdMap.get(bone.parent));
            float[] pm = new float[16];
            parent.globalTransform.get(pm);
            float px = pm[12];
            float py = pm[13];
            float pz = pm[14];
            stroke(0, 255, 0);
            line(x, y, z, px, py, pz);
        }
    }

    // Print hovered bone name
    if (hoveredBone != null) {
        println("Current bone:", hoveredBone.name);
        
        // Draw label for closest bone
        PVector screenPos = boneScreenPositions.get(bones.indexOf(hoveredBone));
        pushStyle();
        hint(DISABLE_DEPTH_TEST);
        textSize(12);
        fill(255, 255, 0);
        textAlign(CENTER, BOTTOM);
        text(hoveredBone.name, screenPos.x, screenPos.y - 15);
        hint(ENABLE_DEPTH_TEST);
        popStyle();
    }
}

  void draw() {
    pushMatrix();
    translate(0, 0, 0);
    shape(mesh);
    popMatrix();
  }
}
