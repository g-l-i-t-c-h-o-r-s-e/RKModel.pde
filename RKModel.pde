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
  PMatrix3D animatedMatrix; // Add this line
  PMatrix3D inverseBindMatrix;
  PMatrix3D globalTransform;
  ArrayList<Bone> children = new ArrayList<>();

  Bone(int id, int parent, String name) {
    this.id = id;
    this.parent = parent;
    this.name = name;
    this.matrix = new PMatrix3D();
    this.animatedMatrix = new PMatrix3D(); // Add this line
    this.inverseBindMatrix = new PMatrix3D();
    this.globalTransform = new PMatrix3D();
  }
}

class BonePose {
  PVector pos;
  float[] quat = new float[4];
  
  BonePose() {
    pos = new PVector();
    quat = new float[]{1.0, 0.0, 0.0, 0.0};
  }
}

class RKAnimation {
  int boneCount;
  ArrayList<AnimationFrame> frames = new ArrayList<>();
  float frameDuration = 0.1;
  boolean playing = false;
  int currentFrame = 0;
  int nextFrame = 1;
  float frameTime = 0;
  long lastUpdate = 0;
}

class AnimationFrame {
  ArrayList<BonePose> bones = new ArrayList<>();
}

class AnimationClip {
  String name;
  int startFrame;
  int endFrame;
  float fps;
  boolean loop;
  
  AnimationClip(String name, int start, int end, float fps) {
    this.name = name;
    this.startFrame = start;
    this.endFrame = end;
    this.fps = fps;
  }
}

class AnimationState {
  AnimationClip clip;
  int currentFrame;
  float frameTime;
  boolean playing;
  boolean loop;
  long lastUpdate;

  AnimationState(AnimationClip clip) {
    this.clip = clip;
    reset();
  }
  
  void reset() {
    currentFrame = clip.startFrame;
    frameTime = 0;
    playing = false;
    lastUpdate = millis();
  }
  
  void update() {
    if (!playing) return;
    
    long currentTime = millis();
    frameTime += (currentTime - lastUpdate) / 1000.0;
    lastUpdate = currentTime;
    
    float frameDuration = 1.0 / clip.fps;
    if (frameTime >= frameDuration) {
      frameTime = 0;
      currentFrame++;
      
      if (currentFrame > clip.endFrame) {
        if (clip.loop) {
          currentFrame = clip.startFrame;
        } else {
          currentFrame = clip.endFrame;
          playing = false;
        }
      }
    }
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
  float scale = 1;
  ArrayList<PVector> skinnedVerts = new ArrayList<>();
  Bone selectedBone = null;
  PVector initialBonePos = new PVector();
  ArrayList<AnimationClip> animations = new ArrayList<>();
  AnimationState currentAnim;
  RKAnimation animationData;
  boolean hasAnimations = false;
  PVector cameraRight, cameraUp;

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
      // Rotate matrix 90 degrees around Z-axis
      PMatrix3D axisCorrection = new PMatrix3D(
        0, -1, 0, 0,
        1, 0, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
      );
      
      // Apply the scaling factor to axisCorrection
      axisCorrection.scale(scale / (scale * 1000));
  
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
  
          // REQUIRED
          normalizeScaling(mat); // Normalize scaling in the bone's local matrix
          mat.scale(scale); // Synchronize scaling between mesh and skeleton
          mat.preApply(axisCorrection); // Apply axisCorrection after normalization
  
          String name = header.readString(data, off + 76, 64);
          Bone bone = new Bone(id, parentId, name);
          bone.matrix = mat;
          bones.add(bone);
          boneIdMap.put(id, i);
  
          // Debug print to verify scaling
          println("Bone ID: " + id + ", Name: " + name);
          printMatrix("Local Matrix", bone.matrix);
      }
  }

  void normalizeScaling(PMatrix3D matrix) {
      float[] m = new float[16];
      matrix.get(m);
  
      // Extract scaling factors
      float sx = sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]);
      float sy = sqrt(m[4] * m[4] + m[5] * m[5] + m[6] * m[6]);
      float sz = sqrt(m[8] * m[8] + m[9] * m[9] + m[10] * m[10]);
  
      // Normalize the matrix to remove unintended scaling
      if (sx != 0) {
          m[0] /= sx;
          m[1] /= sx;
          m[2] /= sx;
      }
      if (sy != 0) {
          m[4] /= sy;
          m[5] /= sy;
          m[6] /= sy;
      }
      if (sz != 0) {
          m[8] /= sz;
          m[9] /= sz;
          m[10] /= sz;
      }
  
      matrix.set(m);
  }

void computeInverseBindMatrices() {
  processingOrder = new ArrayList<>();
  rootBones = new ArrayList<>();

  for (Bone bone : bones) {
    if (bone.parent == -1) {
      rootBones.add(bone);
      processingOrder.add(bone);
      addChildrenRecursive(bone, processingOrder);
    }
  }

  for (Bone bone : processingOrder) {
    if (bone.parent == -1) {
      bone.globalTransform = bone.matrix.get();
    } else {
      Bone parent = bones.get(boneIdMap.get(bone.parent));
      bone.globalTransform = parent.globalTransform.get();
      bone.globalTransform.apply(bone.matrix);
    }
    bone.inverseBindMatrix = bone.globalTransform.get();
    bone.inverseBindMatrix.invert();
  }
}
  
  void printMatrix(String label, PMatrix3D matrix) {
      float[] m = new float[16];
      matrix.get(m);
      println(label + ":");
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
          readFloat4(data, off) * scale,
          readFloat4(data, off + 4) * scale,
          readFloat4(data, off + 8) * scale
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
  
  void loadAnimations(String animFile) {
    byte[] data = loadBytes(animFile);
    if(data == null) return;
    
    animationData = new RKAnimation();
    int offset = 0x50;
    
    animationData.boneCount = readInt4(data, offset);
    if(animationData.boneCount != bones.size()) {
      println("Animation/model bone count mismatch!");
      return;
    }
    int frameCount = readInt4(data, offset+4);
    int frameType = readInt4(data, offset+8);
    offset += 12;
    
    if(frameType != 4) {
      println("Unsupported animation frame type:", frameType);
      return;
    }

    String csvFile = animFile.replace(".anim", ".csv");
    String[] lines = loadStrings(csvFile);
    if(lines != null) {
      for(String line : lines) {
        String[] parts = split(line, ',');
        if(parts.length == 4) {
          animations.add(new AnimationClip(
            parts[0].replaceAll("\"", "").trim(),
            int(parts[1]), 
            int(parts[2]), 
            float(parts[3])
          ));
        }
      }
    }
    
    for(int f=0; f<frameCount; f++) {
      AnimationFrame frame = new AnimationFrame();
      
      for(int b=0; b<animationData.boneCount; b++) {
        BonePose pose = new BonePose();
        
        float origX = readShort2(data, offset) / 32.0f;
        float origY = readShort2(data, offset+2) / 32.0f;
        float origZ = readShort2(data, offset+4) / 32.0f;
        
        pose.pos.set(
          origX * scale / 1000, 
          origY * scale / 1000, 
          origZ * scale / 1000
        );
        offset += 6;
        
        float w = readShort2(data, offset) / 32767.0;
        float x = (byte)data[offset+2] / 127.0;
        float y = (byte)data[offset+3] / 127.0;
        float z = (byte)data[offset+4] / 127.0;
        offset += 5;

        
        float norm = PApplet.sqrt(w * w + x * x + y * y + z * z);
        pose.quat[0] = w / norm;
        pose.quat[1] = x / norm;
        pose.quat[2] = y / norm;
        pose.quat[3] = z / norm;


        frame.bones.add(pose);
      }
      animationData.frames.add(frame);
    }
    
    hasAnimations = true;
    println("Loaded animation:", animFile);
  }

  void playAnimation(String name) {
    for(AnimationClip clip : animations) {
      if(clip.name.equals(name)) {
        currentAnim = new AnimationState(clip);
        currentAnim.playing = true;
        return;
      }
    }
    println("Animation not found:", name);
  }

  void updateAnimation() {
    if(currentAnim == null || !currentAnim.playing) return;
    currentAnim.update();
    applyBonePoses();
  }

  void applyBonePoses() {
    if (!hasAnimations || currentAnim == null) return;
  
    float t = currentAnim.frameTime * currentAnim.clip.fps;
    int frameA = currentAnim.currentFrame;
    int frameB = min(frameA + 1, currentAnim.clip.endFrame);
  
    // Axis correction (consistent with loadBones)
    PMatrix3D axisCorrection = new PMatrix3D(
      0, -1, 0, 0,
      1, 0, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1
    );
    axisCorrection.scale(scale);
  
    for (int i = 0; i < bones.size(); i++) {
      Bone bone = bones.get(i);
      BonePose pA = animationData.frames.get(frameA).bones.get(i);
      BonePose pB = animationData.frames.get(frameB).bones.get(i);
  
      // Directly use pre-scaled positions from animation data
      PVector animPos = PVector.lerp(pA.pos, pB.pos, t);
      
      // Convert quaternion to rotation matrix
      float[] q = slerp(pA.quat, pB.quat, t);
      PMatrix3D rotMat = quatToMatrix(q);
      normalizeScaling(rotMat);
  
      // Ensure axis correction order is the same as in loadBones
      rotMat.preApply(axisCorrection);
  
      // Apply animation transforms IN LOCAL SPACE
      bone.animatedMatrix = new PMatrix3D();
      bone.animatedMatrix.apply(bone.matrix); // Start with original bind pose
      
      // 1. Apply translation BEFORE rotation
      bone.animatedMatrix.translate(animPos.x, animPos.y, animPos.z);
      bone.animatedMatrix.apply(rotMat);
    }
  
    // Compute global transforms
    for (Bone bone : processingOrder) {
      if (bone.parent == -1) {
        bone.globalTransform = bone.animatedMatrix.get();
      } else {
        Bone parent = bones.get(boneIdMap.get(bone.parent));
        bone.globalTransform.set(parent.globalTransform);
        bone.globalTransform.apply(bone.animatedMatrix);
      }
    }
  
    applySkinning();
  }

  
  
  float[] slerp(float[] qa, float[] qb, float t) {
      float[] qm = new float[4];
      float cosHalfTheta = qa[0]*qb[0] + qa[1]*qb[1] + qa[2]*qb[2] + qa[3]*qb[3];
      
      if (abs(cosHalfTheta) >= 1.0) {
          qm[0] = qa[0]; qm[1] = qa[1]; qm[2] = qa[2]; qm[3] = qa[3];
          return qm;
      }
      
      float halfTheta = acos(cosHalfTheta);
      float sinHalfTheta = sqrt(1.0 - cosHalfTheta*cosHalfTheta);
      
      if (abs(sinHalfTheta) < 0.001) {
          qm[0] = (qa[0]*(1-t) + qb[0]*t);
          qm[1] = (qa[1]*(1-t) + qb[1]*t);
          qm[2] = (qa[2]*(1-t) + qb[2]*t);
          qm[3] = (qa[3]*(1-t) + qb[3]*t);
          return qm;
      }
      
      float ratioA = sin((1-t)*halfTheta)/sinHalfTheta;
      float ratioB = sin(t*halfTheta)/sinHalfTheta;
      
      qm[0] = (qa[0]*ratioA + qb[0]*ratioB);
      qm[1] = (qa[1]*ratioA + qb[1]*ratioB);
      qm[2] = (qa[2]*ratioA + qb[2]*ratioB);
      qm[3] = (qa[3]*ratioA + qb[3]*ratioB);
      return qm;
  }
  
  PMatrix3D quatToMatrix(float[] q) {
    float w = q[0], x = q[1], y = q[2], z = q[3];
    return new PMatrix3D(
      1 - 2*y*y - 2*z*z, 2*x*y + 2*z*w,   2*x*z - 2*y*w,   0,
      2*x*y - 2*z*w,   1 - 2*x*x - 2*z*z, 2*y*z + 2*x*w,   0,
      2*x*z + 2*y*w,   2*y*z - 2*x*w,   1 - 2*x*x - 2*y*y, 0,
      0, 0, 0, 1
    );
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

            // Calculate skinning matrix: Global Transform * Inverse Bind Matrix
            PMatrix3D skinningMatrix = new PMatrix3D();
            skinningMatrix.apply(bone.inverseBindMatrix);
            skinningMatrix.apply(bone.globalTransform);  

            // Transform vertex
            PVector transformed = new PVector();
            skinningMatrix.mult(original, transformed);
            transformed.mult(w.weight);
            skinned.add(transformed);
            totalWeight += w.weight;
        }

        // Normalize if weights don't sum to 1.0
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
      }
  }

  boolean selectBone(int mx, int my) {
      selectedBone = null;
      float closestDistance = Float.MAX_VALUE;
  
      for (Bone bone : bones) {
          float[] m = new float[16];
          bone.globalTransform.get(m);
          float x = m[12];
          float y = m[13];
          float z = m[14];
  
          // Get screen position
          float screenX = screenX(x, y, z);
          float screenY = screenY(x, y, z);
          float screenZ = screenZ(x, y, z);
  
          // Skip bones behind the camera
          if (screenZ <= 0) continue;
  
          // Calculate 2D distance to mouse
          float distToMouse = dist(mx, my, screenX, screenY);
  
          // Track closest bone within threshold
          if (distToMouse < 10 && distToMouse < closestDistance) {
              closestDistance = distToMouse;
              selectedBone = bone;
              initialBonePos.set(x, y, z);
          }
      }
  
      return selectedBone != null; // Return true if a bone is selected
  }

  void dragBone(int dx, int dy) {
      if (selectedBone == null) return;
  
      // Calculate translation based on camera orientation
      float sensitivity = 0.01;
      PVector delta = PVector.mult(cameraRight, dx * sensitivity);
      delta.add(PVector.mult(cameraUp, -dy * sensitivity));
  
      // Apply translation to the bone's global transform
      selectedBone.globalTransform.translate(delta.x, delta.y, delta.z);
  
      // Update the bone hierarchy and skinning
      updateBoneHierarchy(selectedBone);
      applySkinning();
  }
  
  void updateBoneHierarchy(Bone bone) {
      if (bone.parent != -1) {
          Bone parent = bones.get(boneIdMap.get(bone.parent));
          PMatrix3D invParent = parent.globalTransform.get();
          invParent.invert();
          bone.matrix.set(bone.globalTransform); // Copy global transform
          bone.matrix.preApply(invParent);       // Apply inverse parent transform
      } else {
          bone.matrix.set(bone.globalTransform); // Root bone's local matrix is its global transform
      }
  
      // Update children recursively
      for (Bone child : bone.children) {
          child.globalTransform.set(bone.globalTransform);
          child.globalTransform.apply(child.matrix);
          updateBoneHierarchy(child);
      }
  }

  void draw() {
    updateAnimation();
    pushMatrix();
    translate(0, 0, 0);
    shape(mesh);
    popMatrix();
    drawBones();
  }
}
