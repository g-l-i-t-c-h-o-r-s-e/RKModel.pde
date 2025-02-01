
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
      for (int i = 0; i < 8; i++) magic += char(data[i]);
      versionMajor = readInt4(data, 8);
      versionMinor = readInt4(data, 12);
      name = readString(data, 16, 64);
      println("RK Header:\nMagic: '"+magic+"'\nVersion: "+versionMajor+"."+versionMinor+"\nName: '"+name+"'");
    } catch (Exception e) {
      println("Header Error: "+e);
    }
  }
  
  String readString(byte[] data, int o, int maxLen) {
    String s = "";
    for (int i = 0; i < maxLen; i++) {
      if (data[o + i] == 0) break;
      s += char(data[o + i]);
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
    PMatrix3D matrix; // Current transformation matrix
    PMatrix3D animatedMatrix; // Matrix used during animation
    PMatrix3D inverseBindMatrix;
    PMatrix3D restPoseMatrix;
    ArrayList<Bone> children;

    Bone(int id, int parent, String name) {
        this.id = id;
        this.parent = parent;
        this.name = name;
        this.matrix = new PMatrix3D();
        this.animatedMatrix = new PMatrix3D();
        this.inverseBindMatrix = new PMatrix3D();
        this.restPoseMatrix = new PMatrix3D();
        this.children = new ArrayList<>();
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
  float frameDuration = 0.1; // 10 FPS by default
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
    frameTime += (currentTime - lastUpdate) / 1000.0; // Update frame time
    lastUpdate = currentTime;

    float frameDuration = 1.0 / clip.fps; // Duration of each frame

    // Advance to the next frame if enough time has passed
    if (frameTime >= frameDuration) {
      frameTime = 0; // Reset frame time
      currentFrame++; // Move to the next frame

      // Handle looping or stopping at the end
      if (currentFrame == clip.endFrame) {
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
  ArrayList<Bone> processingOrder; // = new ArrayList<>();
  ArrayList<Bone> rootBones; // = new ArrayList<>();
  HashMap<Integer, Integer> boneIdMap;
  ArrayList<String> materials = new ArrayList<>();
  SkinningData skinning = new SkinningData();
  ArrayList<AnimationClip> animations = new ArrayList<>();
  AnimationState currentAnim;
  RKAnimation animationData;
  ArrayList<String> animationNames = new ArrayList<String>();
  boolean hasAnimations = false;
  PShape mesh;
  PImage texture;
  float scale = 1;
  ArrayList<PVector> skinnedVerts = new ArrayList<>();
  boolean startup = true;

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
    for (int i = 0; i < 17; i++) {
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
    if (matSec == null) return;
    
    println("\nMaterials:");
    int matSize = 320;
    for (int i=0; i<matSec.count; i++) {
      int off = matSec.offset + i*matSize;
      materials.add(header.readString(data, off, 64));
      println(i+": "+materials.get(materials.size()-1));
    }
  }

  void loadBones(byte[] data) {
      Section boneSec = sections.get(7);
      if (boneSec == null) return;
  
      println("\nBones:");
      this.boneIdMap = new HashMap<>(); // Map bone IDs to their indices in the bones list
      int boneSize = 140; // Size of each bone entry in bytes
  
      // First pass: Load all bones and store them in the bones list
      for (int i = 0; i < boneSec.count; i++) {
          int off = boneSec.offset + i * boneSize; // Calculate offset for the current bone
  
          // Read parent bone ID (0xFFFFFFFF means no parent)
          int parent = readInt4(data, off);
          parent = parent == 0xFFFFFFFF ? -1 : parent;
  
          // Read bone ID
          int id = readInt4(data, off + 4);
  
          // Read number of children (not used directly here, but available if needed)
          int numChildren = readInt4(data, off + 8);
  
          // Read the bone's transformation matrix (row-major order)
          float[] matrixData = new float[16];
          for (int j = 0; j < 16; j++) {
              matrixData[j] = readFloat4(data, off + 12 + j * 4);
          }
  
          // Read the bone's name (64-byte string, null-terminated)
          String name = header.readString(data, off + 76, 64);
  
          // Create the bone object
          Bone bone = new Bone(id, parent, name);
          bone.matrix.set(matrixData); // Set the bone's transformation matrix
          bone.matrix.scale(scale); // Apply scaling to match the mesh
          bone.matrix.transpose(); // Convert from row-major to column-major order
          bone.restPoseMatrix.set(bone.matrix); // Store the rest pose matrix
  
          // Add the bone to the bones list and map its ID to its index
          bones.add(bone);
          boneIdMap.put(id, i);
  
          // Print bone information for debugging
          println(i + ": ID " + id + " " + name + " (Parent: " + parent + ")");
          printMatrix(bone.matrix);
      }
  
      // Second pass: Establish parent-child relationships
      for (Bone bone : bones) {
          if (bone.parent != -1) { // If the bone has a parent
              // Find the parent bone using the boneIdMap
              Bone parentBone = bones.get(boneIdMap.get(bone.parent));
  
              // Add the current bone as a child of its parent
              parentBone.children.add(bone);
          }
      }
  
      // Print hierarchy for debugging
      println("\nBone Hierarchy:");
      for (Bone bone : bones) {
          if (bone.parent == -1) { // Only print root bones
              printBoneHierarchy(bone, 0);
          }
      }
  }
  
  void printBoneHierarchy(Bone bone, int depth) {
      // Indent based on depth to visualize hierarchy
      for (int i = 0; i < depth; i++) {
          print("  ");
      }
      println("- " + bone.name + " (ID: " + bone.id + ")");
  
      // Recursively print children
      for (Bone child : bone.children) {
          printBoneHierarchy(child, depth + 1);
      }
  }
  
  void loadAnimations(String animFile) {
    byte[] data = loadBytes(animFile);
    if (data == null) return;
    
    animationData = new RKAnimation();
    int offset = 0x50;
    
    // Read header with frame type verification
    animationData.boneCount = readInt4(data, offset);
    if (animationData.boneCount != bones.size()) {
        println("Animation/model bone count mismatch!");
        return;
    }
    int frameCount = readInt4(data, offset+4);
    int frameType = readInt4(data, offset+8);
    offset += 12;
    
    // Verify supported frame type
    if (frameType != 4) {
      println("Unsupported animation frame type:", frameType);
      return;
    }

    // Load animation clips with proper CSV parsing
    String csvFile = animFile.replace(".anim", ".csv");
    String[] lines = loadStrings(csvFile);
    if (lines != null) {
      for (String line : lines) {
        String[] parts = split(line, ',');
        if (parts.length == 4) {
          String animName = parts[0].replaceAll("\"", "").trim();
          animations.add(new AnimationClip(
            animName,
            int(parts[1]),
            int(parts[2]),
            float(parts[3])
          ));
          animationNames.add(animName);
        }
      }
    }
    
    // Load frames with coordinate system conversion
    for (int f = 0; f < frameCount; f++) {
      AnimationFrame frame = new AnimationFrame();
      
      for (int b=0; b<animationData.boneCount; b++) {
        BonePose pose = new BonePose();
        
        
        // Position conversion: none
        pose.pos.x = readShort2(data, offset) / 32.0;
        pose.pos.y = readShort2(data, offset+2) / 32.0;
        pose.pos.z = readShort2(data, offset+4) / 32.0;
        offset += 6;
        
        // Quaternion conversion: none
        pose.quat[0] = readShort2(data, offset) / 32767.0;
        pose.quat[1] = (byte)data[offset+2] / 127.0;
        pose.quat[2] = (byte)data[offset+3] / 127.0;
        pose.quat[3] = (byte)data[offset+4] / 127.0;
        offset += 5;
        
        frame.bones.add(pose);
      }
      animationData.frames.add(frame);
    }
    
    hasAnimations = true;
    println("Loaded animation:", animFile);
    println("- Valid Frames:", animationData.frames.size());
    println("- Registered Clips:", animations.size());
  }
  
  void playAnimation(String name, boolean loop) {
    for (AnimationClip clip : animations) {
      if (clip.name.equals(name)) {
        currentAnim = new AnimationState(clip);
        currentAnim.clip.loop = loop;
        currentAnim.clip.fps = 15;
        currentAnim.playing = true;
        println("Playing clip:", name, "for", clip.endFrame - clip.startFrame, "frames");
        return;
      }
    }
    println("Animation not found:", name);
  }

  void updateAnimation() {
    if (currentAnim == null || !currentAnim.playing) return;
    currentAnim.update();
    applyBonePoses();
    applySkinning();
  }

  void applyBonePoses() {
    if (!hasAnimations || currentAnim == null) return;

    float t = currentAnim.frameTime * currentAnim.clip.fps;
    int frameA = currentAnim.currentFrame;
    int frameB = min(frameA + 1, currentAnim.clip.endFrame);

    AnimationFrame poseA = animationData.frames.get(frameA);
    AnimationFrame poseB = animationData.frames.get(frameB);

    for (int i = 0; i < bones.size(); i++) {
      Bone bone = bones.get(i);
      int boneId = bone.id;

      if (boneId >= poseA.bones.size() || boneId >= poseB.bones.size()) continue;

      BonePose pA = poseA.bones.get(boneId);
      BonePose pB = poseB.bones.get(boneId);

      // Position interpolation (existing code remains)
      PVector animPosA = new PVector(pA.pos.x, pA.pos.y, pA.pos.z);
      PVector animPosB = new PVector(pB.pos.x, pB.pos.y, pB.pos.z);
      PVector pos = PVector.lerp(animPosA, animPosB, t);

      // Convert quaternions and interpolate
      float[] qA = { pA.quat[0], pA.quat[1], pA.quat[2], pA.quat[3] };
      float[] qB = { pB.quat[0], pB.quat[1], pB.quat[2], pB.quat[3] };
      
      // You need to apply the quaternion dot product check before performing spherical linear interpolation (slerp). 
      // This ensures that the shortest path is taken during interpolation
      float dot = qA[0] * qB[0] + qA[1] * qB[1] + qA[2] * qB[2] + qA[3] * qB[3];
      if (dot < 0) {
          qB[0] = -qB[0];
          qB[1] = -qB[1];
          qB[2] = -qB[2];
          qB[3] = -qB[3];
      }
      float[] quat = slerp(qA, qB, t);

      // Normalize the interpolated quaternion
      float len = sqrt(quat[0]*quat[0] + quat[1]*quat[1] + quat[2]*quat[2] + quat[3]*quat[3]);
      quat[0] /= len;
      quat[1] /= len;
      quat[2] /= len;
      quat[3] /= len;

      // 1. Create rotation matrix from quaternion
      PMatrix3D rotationMatrix = quatToMatrix(quat);
      //normalizeScaling(rotationMatrix); doesnt help
      
      // 2. Apply translation to the rotated space
      PMatrix3D translationMatrix = new PMatrix3D();
      translationMatrix.translate(pos.x * scale, pos.y * scale, pos.z * scale);
      
      // 3. Combine as Translation * Rotation (T * R)
      translationMatrix.apply(rotationMatrix);
      bone.animatedMatrix = translationMatrix;
      bone.animatedMatrix.scale(scale);
    }
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
    
    float ratioA = sin((1 - t) * halfTheta) / sinHalfTheta;
    float ratioB = sin(t * halfTheta) / sinHalfTheta;
    
    qm[0] = (qa[0]*ratioA + qb[0]*ratioB);
    qm[1] = (qa[1]*ratioA + qb[1]*ratioB);
    qm[2] = (qa[2]*ratioA + qb[2]*ratioB);
    qm[3] = (qa[3]*ratioA + qb[3]*ratioB);
    return qm;
  }

  void computeInverseBindMatrices() {
    for (Bone bone : bones) {
      bone.inverseBindMatrix = bone.matrix.get();
      bone.inverseBindMatrix.invert();
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
  
  // Print Bone Matrix
  void printMatrix(PMatrix3D mat) {
    // PMatrix3D stores values in column-major order
    float[] m = new float[16];
    mat.get(m);
    
    println("Bone Matrix:");
    println(nf(m[0], 1, 4) + " " + nf(m[4], 1, 4) + " " + nf(m[8], 1, 4) + " " + nf(m[12], 1, 4));
    println(nf(m[1], 1, 4) + " " + nf(m[5], 1, 4) + " " + nf(m[9], 1, 4) + " " + nf(m[13], 1, 4));
    println(nf(m[2], 1, 4) + " " + nf(m[6], 1, 4) + " " + nf(m[10], 1, 4) + " " + nf(m[14], 1, 4));
    println(nf(m[3], 1, 4) + " " + nf(m[7], 1, 4) + " " + nf(m[11], 1, 4) + " " + nf(m[15], 1, 4));
    println("----------------------------------------");
  }

  void loadGeometry(byte[] data) {
      Section vertSec = sections.get(3);
      if (vertSec == null) return;
      
      int stride = vertSec.byteLength / vertSec.count;
      println("Vertex stride:",stride,"bytes");
      
      for (int i = 0; i < vertSec.count; i++) {
        int off = vertSec.offset + i*stride;
        
        PVector pos = new PVector(
          readFloat4(data, off) * scale,       // X
          readFloat4(data, off + 4) * scale,   // Y
          readFloat4(data, off + 8) * scale    // Z
        );
          
        PVector uv = new PVector(0, 0);
    if (stride == 16) {
        int u = (data[off+16] & 0xFF) | ((data[off+17] & 0xFF) << 8);
        int v = (data[off+18] & 0xFF) | ((data[off+19] & 0xFF) << 8);
        
        // CORRECTED: Remove the *2.0 scaling and add clamping
        uv.x = constrain(u / 65535.0f, 0, 1);
        uv.y = constrain(1.0f - (v / 65535.0f), 0, 1); // Flip V only
        
    } else if (stride == 20) {
        uv.x = readFloat4(data, off + 16);
        uv.y = 1.0f - readFloat4(data, off + 20);  // Keep V flip
        
        // Add clamping for float UVs if needed
        uv.x = constrain(uv.x, 0, 1);
        uv.y = constrain(uv.y, 0, 1);
    }
        
        vertices.add(pos);
        uvs.add(uv);

        // First 10 UV debug output
        if (i < 10) {
            println("Vertex " + i + " UV: " + 
                nf(uv.x, 0, 3) + ", " + 
                nf(uv.y, 0, 3) + " " +
                (stride == 16 ? "(short)" : "(float)"));
        }
    }
  
      Section faceSec = sections.get(4);
      if (faceSec == null) return;
      
      boolean use32bit = vertices.size() > 65535;
      int indexSize = use32bit ? 4 : 2;
      int triCount = faceSec.byteLength / (indexSize * 3);
      
      println("Loading",triCount,"triangles with",(use32bit ? 32 : 16)+"-bit indices");
      for (int i = 0; i < triCount; i++) {
        int off = faceSec.offset + i * indexSize * 3;
        int[] tri = new int[3];
        
        for (int j = 0; j < 3; j++) {
          if (use32bit) {
            tri[j] = readInt4(data, off + (j*4));
          } else {
            tri[j] = readShort2(data, off + (j*2)) & 0xFFFF;
          }
        }
        triangles.add(tri);
      }
      println("Successfully loaded",triangles.size(),"triangles");
        
      Section weightSec = sections.get(17);
      if (weightSec != null) {
        int weightSize = weightSec.byteLength / weightSec.count;
        for (int i = 0; i < weightSec.count; i++) {
          int off = weightSec.offset + i * weightSize;
          ArrayList<VertexWeight> vWeights = new ArrayList<>();
  
          // Read 4 bone IDs (1 byte each) followed by 4 weights (2 bytes each)
          float totalWeight = 0;
          for (int j = 0; j < 4; j++) {
            int boneId = data[off + j] & 0xFF; // 1-byte bone IDs
            Integer boneIndex = this.boneIdMap.get(boneId);
  
            if (boneIndex == null) {
              println("Missing bone mapping for ID: " + boneId);
              continue;
            }
  
            // Read weight (2 bytes per weight after 4 bone IDs)
            int weightOffset = off + 4 + (j * 2);
            int weightValue = readShort2(data, weightOffset) & 0xFFFF;
            float weight = weightValue / 65535.0f;
  
            if (weight > 0) {
              vWeights.add(new VertexWeight(boneIndex, weight));
              totalWeight += weight;
            }
          }
  
          // Normalize weights to ensure they sum to 1.0
          if (totalWeight > 0) {
            for (VertexWeight w : vWeights) {
              w.weight /= totalWeight;
            }
          }
  
          skinning.weights.add(vWeights);
        }
      } else {
        // Add empty weights if no weight section found
        for (int i = 0; i < vertices.size(); i++) {
          skinning.weights.add(new ArrayList<VertexWeight>());
        }
      }
      println("Loaded " + vertices.size() + " vertices with " + uvs.size() + " UV sets");
    }

  void buildMesh() {
      mesh = createShape();
      mesh.beginShape(TRIANGLES);
      mesh.texture(texture);
      mesh.textureMode(NORMAL);  // Requires UVs in [0,1] range
      mesh.noStroke();
      
      // Verify texture dimensions
      println("Texture size:", texture.width + "x" + texture.height);
      
      for (int[] tri : triangles) {
          for (int i = 0; i < 3; i++) {
              int vertIndex = tri[i];
              PVector v = vertices.get(vertIndex);
              PVector uv = uvs.get(vertIndex);
              
              // Final UV validation
              if (vertIndex < 10) {
                  println("Tri Vert", vertIndex, "UV:", uv.x, uv.y);
              }
              
              mesh.vertex(v.x, v.y, v.z, uv.x, uv.y);
          }
      }
      
      mesh.endShape();
      skinnedVerts = new ArrayList<>(vertices);
      println("Mesh built with", mesh.getVertexCount(), "vertices");
  }

  PMatrix3D quatToMatrix(float[] q) {
    float w = q[0], x = q[1], y = q[2], z = q[3];
    return new PMatrix3D(
      1 - 2*y*y - 2*z*z, 2*x*y - 2*z*w,   2*x*z + 2*y*w,   0,
      2*x*y + 2*z*w,   1 - 2*x*x - 2*z*z, 2*y*z - 2*x*w,   0,
      2*x*z - 2*y*w,   2*y*z + 2*x*w,   1 - 2*x*x - 2*y*y, 0,
      0, 0, 0, 1
    );
  }

  void applySkinning() {
      for (int i = 0; i < vertices.size(); i++) {
          PVector original = vertices.get(i);
          PVector skinned = new PVector();
          ArrayList<VertexWeight> weights = skinning.weights.get(i);
          float totalWeight = 0;
  
          // Normalize weights to ensure they sum to 1.0
          float weightSum = 0;
          for (VertexWeight w : weights) {
              weightSum += w.weight;
          }
          if (weightSum > 0) {
              for (VertexWeight w : weights) {
                  w.weight /= weightSum;
              }
          }
  
          // Apply skinning
          for (VertexWeight w : weights) {
              if (w.boneIndex >= bones.size()) continue;
              Bone bone = bones.get(w.boneIndex);
  
              // Use rest pose matrix just once when the model is initially loaded, probably a better way to do this
              PMatrix3D skinningMatrix = (currentAnim == null || startup == true )
                  ? bone.restPoseMatrix.get() 
                  : bone.animatedMatrix.get();
  
              // Calculate skinning matrix: Global Transform * Inverse Bind Matrix
              skinningMatrix.apply(bone.inverseBindMatrix);
  
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
  
      if (startup) {
          startup = false;
      }
  }
  
  void updateMeshVertices() {
      int vertexIndex = 0;
      for (int[] tri : triangles) {
          for (int j = 0; j < 3; j++) {
              int originalIndex = tri[j]; // Get original vertex index from triangle data
              if (originalIndex < skinnedVerts.size()) {
                  PVector v = skinnedVerts.get(originalIndex); // Fetch skinned position
                  mesh.setVertex(vertexIndex, v.x, v.y, v.z); // Update mesh vertex
              }
              vertexIndex++;
          }
      }
  }

  void normalizeMatrix(PMatrix3D matrix) {
      float[] m = new float[16];
      matrix.get(m);
  
      // Normalize the upper 3x3 rotation/scale part of the matrix
      for (int i = 0; i < 3; i++) {
          float len = sqrt(m[i] * m[i] + m[i + 4] * m[i + 4] + m[i + 8] * m[i + 8]);
          if (len > 0) {
              m[i] /= len;
              m[i + 4] /= len;
              m[i + 8] /= len;
          }
      }
  
      matrix.set(m);
  }
  
  void printSummary() {
    println("\nModel Summary:");
    println("Vertices: " + vertices.size());
    println("Triangles: " + triangles.size());
    println("Bones: " + bones.size());
    println("Materials: " + materials.size());

    // Print bone positions from global transforms
    println("Bone Positions:");
    for (Bone bone : bones) {
      PVector pos = new PVector();
      bone.matrix.mult(pos, pos);
      println(
        "Bone: " + bone.name +
        " Position: " + nf(pos.x, 1, 2) + " " +
        nf(pos.y, 1, 2) + " " + nf(pos.z, 1, 2)
      );
    }
  }

  void drawBonesStatic() {
    fill(255, 255, 0); // Yellow
    noStroke();
    for (Bone bone : bones) {
      PVector pos = new PVector();
      bone.matrix.mult(pos, pos);

      pushMatrix();
      translate(pos.x, pos.y, pos.z);
      sphere(2);
      popMatrix();

      if (bone.parent != -1) {
        Bone parent = bones.get(bone.parent);
        PVector parentPos = new PVector();
        parent.matrix.mult(parentPos, parentPos);
        stroke(0, 255, 0);
        line(pos.x, pos.y, pos.z, parentPos.x, parentPos.y, parentPos.z); // Draw line to parent bone
      }
    }
  }
  void drawBonesAnimated() {
    fill(255, 255, 0); // Yellow
    noStroke();
    for (Bone bone : bones) {
      PVector pos = new PVector();
      bone.animatedMatrix.mult(pos, pos);

      pushMatrix();
      translate(pos.x, pos.y, pos.z);
      sphere(2);
      popMatrix();

      if (bone.parent != -1) {
        Bone parent = bones.get(bone.parent);
        PVector parentPos = new PVector();
        parent.animatedMatrix.mult(parentPos, parentPos);
        stroke(0, 255, 0);
        line(pos.x, pos.y, pos.z, parentPos.x, parentPos.y, parentPos.z); // Draw line to parent bone
      }
    }
  }

  void draw() {
    updateAnimation();
    shape(mesh);
  }
}
