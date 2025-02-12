/*******************************************************************************
 * Animated MLP Gameloft RK Model Loader/Renderer for Processing 4 (WIP)
 * https://gist.github.com/g-l-i-t-c-h-o-r-s-e/5590148123825db0205a1ff0d0428f0e
 ********************************************************************************/

import processing.data.XML;
import java.util.Map;
import java.util.regex.*;
import java.util.Collections;

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
  int currentStartFrame;
  int currentEndFrame;
  int currentFrame;
  float frameTime;
  boolean playing;
  long lastUpdate;

  AnimationState(AnimationClip clip, int startFrame, int endFrame) {
    this.clip = clip;
    this.currentStartFrame = startFrame;
    this.currentEndFrame = endFrame;
    reset();
  }

  void reset() {
      currentFrame = currentStartFrame;
      frameTime = 0;
      playing = true; // Force playing state on reset
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

      // Loop or stop when exceeding currentEndFrame
      if (currentFrame > currentEndFrame) {
        if (clip.loop) {
          currentFrame = currentStartFrame; // Loop to adjusted start frame
        } else {
          currentFrame = currentEndFrame;
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

class Submesh {
  String name;
  String xmlID;
  boolean defaultVisible;
  int trianglesCount;
  ArrayList<int[]> triangles;
  int[] vertexIndices;
  int offset;
  int material;
  int unknown;
  boolean currentVisible;

  Submesh(String name, int trianglesCount, int offset, int material, int unknown) {
    this.name = name;
    this.trianglesCount = trianglesCount;
    this.offset = offset;
    this.material = material;
    this.unknown = unknown;
    this.triangles = new ArrayList<>();
    this.currentVisible = true;
  }
}


class AnimVisibilityData {
  HashMap<String, ArrayList<Submesh>> objectDefinitions;  // Maps object names to their submeshes
  HashMap<String, ArrayList<FrameVisibility>> animations; // Maps animation names to frame data

  AnimVisibilityData() {
    objectDefinitions = new HashMap<>();
    animations = new HashMap<>();
  }
}

class FrameVisibility {
  int frameIndex;
  HashMap<String, Boolean> submeshVisibility = new HashMap<>();
  EyeState eyeState;

  FrameVisibility(int index) {
    frameIndex = index;
  }
}

class EyeState {
  boolean blink;
  EyeMode mode;
  
  EyeState(EyeMode mode, boolean blink) {
    this.mode = mode;
    this.blink = blink;
  }
}

enum EyeMode {
  NONE,
  OPEN,
  CLOSED,
  HAPPY,
  FROWN
}

AnimVisibilityData parseAnimVisibilityXML(String xmlPath, RKModel model) {
    AnimVisibilityData data = new AnimVisibilityData();

    String[] lines = loadStrings(xmlPath);
    String xmlContent = join(lines, "\n");
    xmlContent = xmlContent.replaceFirst("^<\\?xml[^>]+\\?>", "").trim();
    xmlContent = "<root>" + xmlContent + "</root>";

    XML xml = parseXML(xmlContent);
    if (xml == null) {
        println("Failed to parse XML");
        return data;
    }

    XML meshListElement = xml.getChild("MeshList");
    if (meshListElement != null) {
        XML[] meshObjects = meshListElement.getChildren();
        for (XML obj : meshObjects) {
            String objectName = obj.getName();
            ArrayList<Submesh> submeshes = new ArrayList<>();

            XML[] subObjects = obj.getChildren("SubObject");
            for (XML subObj : subObjects) {
                String xmlID = subObj.getString("ID");
                String modelName = subObj.getString("Name");
                boolean defaultVisible = subObj.getString("DefaultVisible").equals("1");

                if (xmlID == null || xmlID.isEmpty()) {
                    xmlID = "submesh_" + modelName.toLowerCase().replace(" ", "_");
                }
                
                for (Submesh sm : model.submeshes) {
                    if (sm.name.equals(modelName)) {
                        sm.xmlID = xmlID;
                        sm.defaultVisible = defaultVisible;
                        submeshes.add(sm);
                        println("Matched submesh:", sm.name, "with XML ID:", xmlID);
                        break;
                    }
                }
            }
            data.objectDefinitions.put(objectName, submeshes);
        }
    }

    XML animListElement = xml.getChild("AnimationList");
    if (animListElement != null) {
        XML[] anims = animListElement.getChildren("Animation");
        println("Found " + anims.length + " animations in XML");
        
        for (XML anim : anims) {
            String animName = anim.getString("Name");
            if (animName == null) {
                println("Animation missing Name attribute");
                continue;
            }
            ////println("Processing animation: " + animName);
            
            ArrayList<FrameVisibility> frames = new ArrayList<>();
            XML[] frameElements = anim.getChildren("Frame");
            ////println("- Frames found: " + frameElements.length);
            
            for (XML frameEl : frameElements) {
                int index = frameEl.getInt("Index");
                if (frameEl.hasAttribute("Index") == false) {
                    println("Frame missing Index attribute");
                    continue;
                }
                FrameVisibility fv = new FrameVisibility(index);
                
                // Process EyeSet
                XML[] eyeSets = frameEl.getChildren("EyeSet");
                if (eyeSets.length > 0) {
                    XML eyes = eyeSets[0];
                    String open = eyes.getString("Open", "NONE").toUpperCase();
                    boolean blink = eyes.getString("EnableBlink", "0").equals("1");
                    
                    try {
                        EyeMode mode = EyeMode.valueOf(open);
                        fv.eyeState = new EyeState(mode, blink);
                        ////println("Frame " + index + ": EyeSet " + mode + ", Blink: " + blink);
                    } catch (Exception e) {
                        println("Invalid EyeMode: " + open);
                    }
                }
                
                // Process SubObjects
                XML[] subObjs = frameEl.getChildren("SubObject");
                for (XML subObj : subObjs) {
                    String xmlID = subObj.getString("ID");
                    String show = subObj.getString("Show", "0");
                    boolean visible = show.equals("1");
                    if (xmlID != null) {
                        fv.submeshVisibility.put(xmlID, visible);
                        ////println("Frame " + index + ": SubObject " + xmlID + " visible=" + visible);
                    }
                }
                
                frames.add(fv);
            }
            data.animations.put(animName, frames);
            ////println("Added animation '" + animName + "' with " + frames.size() + " frames");
        }
    }

    return data;
}

String getEyeSubmeshName(EyeMode mode) {
    switch (mode) {
        case CLOSED:
            return "eyes_shut";
        case OPEN:
            return "eyes_open";
        case HAPPY:
            return "eyes_happy";
        case FROWN:
            return "eyes_frown";
        default:
            return "";
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
  Bone mouthBone;
  Bone headBone;
  boolean modulateMouth = false;
  float mouthModulationSensitivity = 0.1;
  float mouthModulationSmoothing = 0.5;
  float smoothedAmplitude = 0;
  float currentAmplitude = 0;
  ArrayList<String> materials = new ArrayList<>();
  int uvOffset;
  String uvFormat;
  float uvScale;
  SkinningData skinning = new SkinningData();
  ArrayList<AnimationClip> animations = new ArrayList<>();
  AnimationState currentAnim;
  RKAnimation animationData;
  ArrayList<String> animationNames = new ArrayList<String>();
  boolean hasAnimations = false;
  AnimationState outgoingAnim = null;
  AnimationState incomingAnim = null;
  float blendFactor = 0.0f;
  float blendDuration = 0.3f; // Transition duration in seconds
  long blendStartTime = 0;
  PShape mesh;
  PShape mainGeometry;
  ArrayList<Submesh> submeshes = new ArrayList<>();
  HashMap<String, Submesh> submeshMap = new HashMap<>();
  HashMap<Submesh, PShape> childShapeMap = new HashMap<>();  
  Map<Integer, List<Submesh>> setMap = new HashMap<>();
  List<Submesh> defaultNonEyeSubmeshes = new ArrayList<>();
  List<Submesh> defaultEyeSubmeshes = new ArrayList<>();
  List<Integer> availableSets = new ArrayList<>();
  int selectedSet = 0;
  ArrayList<PShape> meshParts = new ArrayList<>();
  ArrayList<PShape> childShapes = new ArrayList<PShape>();
  AnimVisibilityData visibilityData;
  ArrayList<PImage> textures = new ArrayList<PImage>();
  float scale = 1;
  int frameDur;
  ArrayList<PVector> skinnedVerts = new ArrayList<>();
  boolean startup = true;
  String animXML;
  boolean hideSubmesh = false;
  Submesh initialEyeSubmesh = null;
  Submesh currentEyeSubmesh = null; 
  boolean isBlinking = false;
  int blinkCounter = 0;
  int blinkDuration = 3; // Number of frames to keep eyes shut
  String currentEyeMode = "open"; // Track current eye mode outside of blinking
  String anim_File;
  boolean isInTransition() {
      return outgoingAnim != null || incomingAnim != null;
  }
  
  
  
  String readString(byte[] data, int o, int maxLen) {
    String s = "";
    for (int i = 0; i < maxLen; i++) {
      if (data[o + i] == 0) break;
      s += char(data[o + i]);
    }
    return s.trim();
  }

  RKModel(String filename) {
    byte[] data = loadBytes(filename);
    //texture = tex;
    header = new RKHeader(data);
    
    if (!header.magic.equals("RKFORMAT")) return;
        
    loadSections(data);
    readAttributes(data);
    readSubmeshInfo(data);
    loadMaterials(data);
    loadBones(data);
    findMouthBone();
    loadGeometry(data);
    computeInverseBindMatrices();
    buildMesh();
    applySkinning();
    
    String getFiles = modelFile;
    getFiles = getXMLFile(getFiles);

    loadVisibilityXML(modelFolder + getFiles + ".xml");
    printSummary();
    sections.clear(); // clear stuff up for now
    sections = null; // clear stuff up for now
    data = null;    // clear stuff up for now
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
  
  void readAttributes(byte[] data) {
      Section attrSec = sections.get(13);
      if (attrSec == null) return;
  
      int offset = attrSec.offset;
      int count = attrSec.count;
  
      for (int i = 0; i < count; i++) {
          int attributeType = readShort2(data, offset);
          int attributeOffset = data[offset + 2] & 0xFF;
          int attributeFormat = data[offset + 3] & 0xFF;
  
          if (attributeType == 1030) {
              this.uvOffset = attributeOffset;
              this.uvFormat = "H"; // Unsigned short
              this.uvScale = 2;
          } else if (attributeType == 1026) {
              this.uvOffset = attributeOffset;
              this.uvFormat = "f"; // Float
              this.uvScale = 1;
          }
  
          offset += 4; // Move to the next attribute
      }
  }
  
    String getCSVFile(String filename) {
    String[][] patterns = {
      {"type01", "pony_type01"},
      {"type02", "pony_type01"},
      {"type03", "pony_type03"},
      {"type04", "pony_type01"},
      {"type05", "pony_type01"},
      {"type06", "pony_type06"},
      {"type07", "pony_type07"},
      {"type08", "pony_type08"},
      {"type09", "pony_type09"},
      {"type10", "pony_type10"},
      {"type11", "pony_type11_timech_lod1"},
      {"type12", "pony_type12"},
      {"type13", "pony_type13"}
    };
    
    for (String[] pattern : patterns) {
      if (filename.contains(pattern[0])) {
        return pattern[1];
      }
    }
    
    return null;
  }

    String getXMLFile(String filename) {
    String[][] patterns = {
      {"type01", "pony_type01"},
      {"type02", "pony_type01"},
      {"type03", "pony_type03"},
      {"type04", "pony_type01"},
      {"type05", "pony_type01"},
      {"type06", "pony_type06"},
      {"type07", "pony_type07"},
      {"type08", "pony_type08"},
      {"type09", "pony_type09"},
      {"type10", "pony_type10"},
      {"type11", "pony_type13"},
      {"type12", "pony_type10"},
      {"type13", "pony_type13"}
    };
    
    for (String[] pattern : patterns) {
      if (filename.contains(pattern[0])) {
        return pattern[1];
      }
    }
    
    return null;
  }
  
    String getAnimFile(String filename) {
    String[][] patterns = {
      {"type01", "pony_type01.anim"},
      {"type02", "pony_type01.anim"},
      {"type03", "pony_type03.anim"},
      {"type04", "pony_type01.anim"},
      {"type05", "pony_type01.anim"},
      {"type06", "pony_type06.anim"},
      {"type07", "pony_type07.anim"},
      {"type08", "pony_type08.anim"},
      {"type09", "pony_type09.anim"},
      {"type10", "pony_type10.anim"},
      {"type11", "pony_type11_timech_lod1.anim"},
      {"type12", "pony_type12.anim"},
      {"type13", "pony_type13.anim"}
    };
    
    for (String[] pattern : patterns) {
      if (filename.contains(pattern[0])) {
        return pattern[1];
      }
    }
    
    return null;
  }
  
  void readSubmeshInfo(byte[] data) {
      Section submeshNamesSec = sections.get(16); // SUBMESH_NAMES section
      Section submeshInfoSec = sections.get(1); // SUBMESH_INFO section
       
      if (submeshNamesSec == null || submeshInfoSec == null) return;
  
      ArrayList<String> submeshNames = new ArrayList<>();
      int offset = submeshNamesSec.offset;
      for (int i = 0; i < submeshNamesSec.count; i++) {
          submeshNames.add(readString(data, offset, 64));
          offset += 64;
      }
  
      offset = submeshInfoSec.offset;
      for (int i = 0; i < submeshInfoSec.count; i++) {
          int triangles = readInt4(data, offset);
          int triangleOffset = readInt4(data, offset + 4);
          int materialIndex = readInt4(data, offset + 8);
          int unknown = readInt4(data, offset + 12);
  
          Submesh submesh = new Submesh(
              submeshNames.get(i),
              triangles,
              triangleOffset,
              materialIndex,
              unknown
          );
          println("Submesh [" + i + "] Triangle offset: "+ submesh.offset);
          submeshes.add(submesh);
          offset += 16;
      }
  }

  void loadMaterials(byte[] data) {
    Section matSec = sections.get(2);
    if (matSec == null) return;
    
    println("\nMaterials:");
    int matSize = matSec.byteLength / matSec.count;
    for (int i = 0; i < matSec.count; i++) {
      int off = matSec.offset + i * matSize;
      String matName = header.readString(data, off, 64);
      materials.add(matName);
      
      // Load texture for each material and add to the list
      PImage tex = loadImage(textureFolder + matName + ".png");
      if (tex != null) {
        textures.add(tex);
      } else {
        println("Warning: Failed to load texture for material " + matName);
        textures.add(null); // Add null as a placeholder
      }
      println(i + ": " + matName);
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

  private void findMouthBone() {
      for (Bone b : bones) {
          if (b.name.toLowerCase().endsWith("_bn_mouth") || b.name.toLowerCase().endsWith("_bn_jaw")) {
              mouthBone = b;
              println("Found mouth bone: " + b.name);
          }
          else if (b.name.toLowerCase().endsWith("_bn_head")) {
              headBone = b;
              println("Found head bone: " + b.name);
          }
      }
  }
  
  private void modulateMouthBone() {
      if (mouthBone == null || !modulateMouth || currentAmplitude == 0) return;
  
      // Smooth the amplitude
      smoothedAmplitude = mouthModulationSmoothing * smoothedAmplitude 
          + (1 - mouthModulationSmoothing) * currentAmplitude;
  
      // Calculate modulation
      float modulation = smoothedAmplitude * mouthModulationSensitivity;
  
      // Get vertices influenced by the jaw/mouth bone
      ArrayList<Integer> jawVertices = getJawVertices();
  
      // Apply modulation directly to the vertices
      for (int vertexIndex : jawVertices) {
          PVector vertex = skinnedVerts.get(vertexIndex);
          vertex.y += modulation; // Adjust Y-axis (or any axis) based on modulation
      }
  }

  ArrayList<Integer> getJawVertices() {
      ArrayList<Integer> jawVertices = new ArrayList<>();
      for (int i = 0; i < skinning.weights.size(); i++) {
          ArrayList<VertexWeight> weights = skinning.weights.get(i);
          for (VertexWeight w : weights) {
              if (w.boneIndex == mouthBone.id) {
                  jawVertices.add(i);
                  break;
              }
          }
      }
      return jawVertices;
  }
  
  
  public void enableMouthModulation(boolean enable) {
      modulateMouth = enable;
  }

  public void setMouthModulationSensitivity(float sensitivity) {
      mouthModulationSensitivity = sensitivity;
  }

  public void setMouthModulationSmoothing(float smoothing) {
      mouthModulationSmoothing = smoothing;
  }

  public void setAmplitude(float amp) {
      currentAmplitude = amp;
  }


  void loadAnimations(String anim_File) {
    byte[] data = loadBytes(anim_File);
    if (data == null) return;
    
    animationData = new RKAnimation();
    int offset = 0x50;
    
    // Read header with frame type verification
    animationData.boneCount = readInt4(data, offset);
    if (animationData.boneCount != bones.size()) {
        println("Animation/model bone count mismatch!", anim_File, "\nAnimation Bones:"+animationData.boneCount, "Mesh Bones "+bones.size());
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
    String getFiles = modelFile;
    animXML = modelFolder + getXMLFile(getFiles) + ".xml";
    
    String csvFile = modelFolder + getCSVFile(getFiles) + ".csv";
    println(csvFile);
    println(animXML);
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
    println("Loaded animation:", anim_File);
    println("- Valid Frames:", animationData.frames.size());
    println("- Registered Clips:", animations.size());
  }
  
  void playAnimation(String name, boolean loop, int startFrame, int endFrame) {
      for (AnimationClip clip : animations) {
          if (clip.name.equals(name)) {
              int adjustedStart = clip.startFrame + startFrame; // Relative to clip's start
              int adjustedEnd = clip.startFrame + endFrame;     // Relative to clip's start
  
              // Handle special cases:
              if (startFrame == 0 && endFrame == 0) {
                  // Use the clip's default frames
                  adjustedStart = clip.startFrame;
                  adjustedEnd = clip.endFrame;
              } else if (endFrame == 0) {
                  // Use custom start + clip's natural end
                  adjustedStart = clip.startFrame + startFrame;
                  adjustedEnd = clip.endFrame;
              }
  
              // Clamp values to valid ranges
              adjustedStart = constrain(adjustedStart, clip.startFrame, clip.endFrame);
              adjustedEnd = constrain(adjustedEnd, clip.startFrame, clip.endFrame);
  
              // Ensure start <= end
              if (adjustedStart > adjustedEnd) {
                  adjustedStart = clip.startFrame;
                  adjustedEnd = clip.endFrame;
                  println("Invalid frame range. Using default.");
              }
  
                AnimationState newAnim = new AnimationState(clip, adjustedStart, adjustedEnd);
                newAnim.clip.loop = loop;
                newAnim.playing = true;

                if (currentAnim != null) {
                    outgoingAnim = currentAnim;
                    outgoingAnim.playing = false; // Freeze outgoing animation
                    incomingAnim = newAnim;
                    blendFactor = 0.0f;
                    blendStartTime = millis();
                } else {
                    currentAnim = newAnim;
                }

                println("Playing clip:", name, "from", adjustedStart, "to", adjustedEnd);
                return;
            }
        }
        println("Animation not found:", name);
    }
  
  
  void updateAnimation() {
      if (outgoingAnim != null && incomingAnim != null) {
          incomingAnim.update();

          long currentTime = millis();
          float elapsed = (currentTime - blendStartTime) / 1000.0f;
          blendFactor = elapsed / blendDuration;

          if (blendFactor >= 1.0f) {
              currentAnim = incomingAnim;
              outgoingAnim = null;
              incomingAnim = null;
              blendFactor = 0.0f;
          }
      } else if (currentAnim != null && currentAnim.playing) {
          currentAnim.update();
      }
      if (currentAnim != null && hasAnimations) {
          int currentFrame = currentAnim.currentFrame;
          if (currentFrame > currentAnim.currentEndFrame) {
              if (currentAnim.clip.loop) {
                  currentAnim.currentFrame = currentAnim.currentStartFrame; // Loop to adjusted start
              } else {
                  currentAnim.playing = false;
              }
          }
          updateVisibilityForFrame(currentAnim.clip.name, (currentFrame - currentAnim.currentStartFrame));
      }
      
      applyBonePoses();
      applySkinning();
  }
  

  void applyBonePoses() {
    if (!hasAnimations) return;
      if (outgoingAnim != null && incomingAnim != null) {
          for (int i = 0; i < bones.size(); i++) {
              Bone bone = bones.get(i);
              int boneId = bone.id;
  
              BonePose poseOutgoing = getInterpolatedPose(outgoingAnim, boneId);
              BonePose poseIncoming = getInterpolatedPose(incomingAnim, boneId);
  
              PVector pos = PVector.lerp(poseOutgoing.pos, poseIncoming.pos, blendFactor);
  
              //cant forget teh dot product check
              float[] qOut = poseOutgoing.quat;
              float[] qIn = poseIncoming.quat;
              float dot = qOut[0] * qIn[0] + qOut[1] * qIn[1] + qOut[2] * qIn[2] + qOut[3] * qIn[3];
              if (dot < 0) {
                  qIn = new float[]{-qIn[0], -qIn[1], -qIn[2], -qIn[3]};
              }
              float[] quat = slerp(qOut, qIn, blendFactor);
              // -----------------------------------------
  
              PMatrix3D rotationMatrix = quatToMatrix(quat);
              PMatrix3D translationMatrix = new PMatrix3D();
              translationMatrix.translate(pos.x * scale, pos.y * scale, pos.z * scale);
              translationMatrix.apply(rotationMatrix);
              bone.animatedMatrix = translationMatrix;
              bone.animatedMatrix.scale(scale);
          }
      } else if (currentAnim != null) {

          float t = currentAnim.frameTime * currentAnim.clip.fps;
          int frameA = currentAnim.currentFrame;
          int frameB = min(frameA + 1, currentAnim.currentEndFrame);

          AnimationFrame poseA = animationData.frames.get(frameA);
          AnimationFrame poseB = animationData.frames.get(frameB);

          for (int i = 0; i < bones.size(); i++) {
            Bone bone = bones.get(i);
            int boneId = bone.id;
      
            if (boneId >= poseA.bones.size() || boneId >= poseB.bones.size()) continue;
      
            BonePose pA = poseA.bones.get(boneId);
            BonePose pB = poseB.bones.get(boneId);
      
            // Position interpolation
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
          applySkinning();
      }
  }

  private BonePose getInterpolatedPose(AnimationState animState, int boneId) {
      if (animState == null || boneId < 0 || boneId >= animationData.boneCount) {
          return new BonePose();
      }
  
      int frameA = animState.currentFrame;
      int frameB = min(frameA + 1, animState.currentEndFrame);
      float t = animState.frameTime * animState.clip.fps;
  
      AnimationFrame frameA_data = animationData.frames.get(frameA);
      AnimationFrame frameB_data = animationData.frames.get(frameB);
  
      BonePose pA = frameA_data.bones.get(boneId);
      BonePose pB = frameB_data.bones.get(boneId);
  
      BonePose result = new BonePose();
      result.pos = PVector.lerp(pA.pos, pB.pos, t);
  
      //cant forget teh dot product check
      float[] qA = pA.quat;
      float[] qB = pB.quat;
      float dot = qA[0] * qB[0] + qA[1] * qB[1] + qA[2] * qB[2] + qA[3] * qB[3];
      if (dot < 0) {
          qB = new float[]{-qB[0], -qB[1], -qB[2], -qB[3]};
      }
      result.quat = slerp(qA, qB, t);
      return result;
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
  
  
  PMatrix3D quatToMatrix(float[] q) {
    float w = q[0], x = q[1], y = q[2], z = q[3];
    return new PMatrix3D(
      1 - 2*y*y - 2*z*z, 2*x*y - 2*z*w,   2*x*z + 2*y*w,   0,
      2*x*y + 2*z*w,   1 - 2*x*x - 2*z*z, 2*y*z - 2*x*w,   0,
      2*x*z - 2*y*w,   2*y*z + 2*x*w,   1 - 2*x*x - 2*y*y, 0,
      0, 0, 0, 1
    );
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
      // Read attributes first to get UV format
      readAttributes(data);
      
      Section vertSec = sections.get(3);
      if (vertSec != null) {
          int stride = vertSec.byteLength / vertSec.count;
          println("Vertex stride:", stride, "bytes");
  
          for (int i = 0; i < vertSec.count; i++) {
              int off = vertSec.offset + i * stride;
              PVector pos = new PVector(
                  readFloat4(data, off) * scale,
                  readFloat4(data, off + 4) * scale,
                  readFloat4(data, off + 8) * scale
              );
  
              PVector uv = new PVector(0, 0);
              // Handle UVs based on stride
              if (stride == 16 || stride == 28) {
                  // Isnt this calculated in readAttributes?
                  //int uvOffset = (stride == 28) ? 20 : 12; // Adjust for 28-byte stride
                  int u = readShort2(data, off + uvOffset);
                  int v = readShort2(data, off + uvOffset + 2);
                  uv.x = u / 32767.0f;
                  uv.y = v / 32767.0f;
              } else if (stride == 20) {
                  float u_float = readFloat4(data, off + 12);
                  float v_float = readFloat4(data, off + 16);
                  uv.x = u_float;
                  uv.y = v_float;
              }

              //wtf lol
              uv.y = (uv.y + 1.0f) / 2.0f;
              uv.y *= this.uvScale;

              vertices.add(pos);
              uvs.add(uv);
          }
      }
  
      Section faceSec = sections.get(4);
      if (faceSec != null) {
          boolean use32bit = vertices.size() > 65535;
          int indexSize = use32bit ? 4 : 2;
          int triCount = faceSec.byteLength / (indexSize * 3);
          int bytesPerTriangle = 3 * indexSize;

          println("Loading", triCount, "triangles with", (use32bit ? 32 : 16) + "-bit indices");
          for (int i = 0; i < triCount; i++) {
              int off = faceSec.offset + i * indexSize * 3;
              int[] tri = new int[3];
              
              for (int j = 0; j < 3; j++) {
                  if (use32bit) {
                      tri[j] = readInt4(data, off + (j * 4));
                  } else {
                      tri[j] = readShort2(data, off + (j * 2)) & 0xFFFF;
                  }
              }
              triangles.add(tri);
          }
          println("Successfully loaded", triangles.size(), "triangles");
      
  
        if (submeshes != null && !submeshes.isEmpty()) {
            for (Submesh submesh : submeshes) {
                submeshMap.put(submesh.name, submesh);

                // Calculate byte offset using index size
                int start = faceSec.offset + (submesh.offset * indexSize);
                
                // Debug: Print submesh info
                println("Loading submesh: " + submesh.name + 
                        ", start: " + start + 
                        ", triangles: " + submesh.trianglesCount);
        
                // Ensure the start offset is within bounds
                if (start < 0 || start >= data.length) {
                    println("Error: Invalid start offset for submesh " + submesh.name);
                    continue;
                }
        
                for (int i = 0; i < submesh.trianglesCount; i++) {
                    // Calculate the offset for the current triangle
                    int off = start + (i * bytesPerTriangle);
        
                    // Ensure the offset is within bounds
                    if (off + bytesPerTriangle > data.length) {
                        println("Error: Invalid triangle offset for submesh " + submesh.name);
                        break;
                    }
        
                    int[] tri = new int[3];
                    for (int j = 0; j < 3; j++) {
                        if (use32bit) {
                            tri[j] = readInt4(data, off + (j * 4));
                        } else {
                            tri[j] = readShort2(data, off + (j * 2)) & 0xFFFF;
                        }
                    }
                    submesh.triangles.add(tri);
                }
            }
        }
        
        for (Submesh submesh : submeshes) {
            ArrayList<Integer> indicesList = new ArrayList<>();
            for (int[] tri : submesh.triangles) {
                for (int idx : tri) {
                    indicesList.add(idx);
                }
            }
            submesh.vertexIndices = new int[indicesList.size()];
            for (int i = 0; i < indicesList.size(); i++) {
                submesh.vertexIndices[i] = indicesList.get(i);
            }
            submesh.triangles.clear(); // Free memory
            submesh.triangles = null;
        }
     }

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
    processSubmeshesIntoSets();
  }

  void processSubmeshesIntoSets() {
      setMap.clear();
      defaultNonEyeSubmeshes.clear();
      defaultEyeSubmeshes.clear();
      availableSets.clear();
  
      for (Submesh submesh : submeshes) {
          String name = submesh.name;
          Matcher matcher = Pattern.compile("_(\\d+)$").matcher(name);
          if (matcher.find()) {
              int setNum = Integer.parseInt(matcher.group(1));
              setMap.computeIfAbsent(setNum, k -> new ArrayList<>()).add(submesh);
          } else {
              if (name.matches(".*eyes_.*")) {
                  defaultEyeSubmeshes.add(submesh);
              } else {
                  defaultNonEyeSubmeshes.add(submesh);
              }
          }
      }
  
      availableSets.addAll(setMap.keySet());
      Collections.sort(availableSets);
  
      if (!availableSets.isEmpty()) {
          selectedSet = availableSets.get(0);
      } else {
          selectedSet = -1;
      }
  }

  void buildMesh() {
    //free memory
    if (mesh != null) {
        mesh = null;
        for (PShape child : childShapes) {
            child = null;
        }
        childShapes.clear();
        childShapeMap.clear();
    }    

      ArrayList<Submesh> orderedSubmeshes = new ArrayList<>();
      Submesh mainSubmesh = null;
  
      if (!availableSets.isEmpty()) {
          List<Submesh> selectedSetSubmeshes = setMap.get(selectedSet);
          if (selectedSetSubmeshes == null) {
              println("Error: Selected set not available.");
              return;
          }
  
          // Find main submesh in the selected set
          for (Submesh submesh : selectedSetSubmeshes) {
              String baseName = submesh.name.replaceAll("_\\d+$", "");
              if (baseName.matches(".*_body.*$")) {
                  mainSubmesh = submesh;
                  break;
              }
          }
          if (mainSubmesh == null) {
              println("Error: No main submesh found in selected set.");
              return;
          }
  
          orderedSubmeshes.add(mainSubmesh);
  
          // Add other submeshes from the selected set
          for (Submesh submesh : selectedSetSubmeshes) {
              if (submesh != mainSubmesh) {
                  orderedSubmeshes.add(submesh);
              }
          }
  
          // Add default non-eye submeshes
          orderedSubmeshes.addAll(defaultNonEyeSubmeshes);
  
          // Add eye submeshes
          orderedSubmeshes.addAll(defaultEyeSubmeshes);
          
          } else {
              // Fallback to original logic if no sets
              for (Map.Entry<String, Submesh> entry : submeshMap.entrySet()) {
                  if (entry.getKey().matches(".*_body.*$")) {
                      mainSubmesh = entry.getValue();
                      break;
                  }
              }
              if (mainSubmesh == null) {
                  println("Error: No main submesh found.");
                  return;
              }
      
              orderedSubmeshes.add(mainSubmesh);
      
              for (Submesh submesh : submeshes) {
                  if (submesh == mainSubmesh) continue;
                  if (submesh.name.matches(".*eyes_.*")) continue;
                  orderedSubmeshes.add(submesh);
              }
      
              for (Submesh submesh : submeshes) {
                  if (submesh.name.matches(".*eyes_.*")) {
                      orderedSubmeshes.add(submesh);
                  }
              }
          }
  
      submeshes = orderedSubmeshes; //rebuild submesh list with the new order
  
      // Build the mesh shape
      mesh = createShape(GROUP);
      mainGeometry = createSubmeshShape(mainSubmesh);
      mesh.addChild(mainGeometry);
  
      childShapes.clear();
      childShapeMap.clear();
  
      for (int i = 1; i < submeshes.size(); i++) {
          Submesh submesh = submeshes.get(i);
          PShape childShape = createSubmeshShape(submesh);
          mesh.addChild(childShape);
          childShapes.add(childShape);
          childShapeMap.put(submesh, childShape);
          println("Submesh: " + submesh.name + ", Vertex Count: " + childShape.getVertexCount());
      }
  
      for (PShape child : childShapes) {
          toggleChildVisibility(child, false);
      }
  
      //Toggle initial visibility of some submeshes
      for (Submesh submesh : submeshes) {
          if (submesh.name.matches(".*eyes_open.*") && childShapeMap.containsKey(submesh)) {
              toggleChildVisibility(childShapeMap.get(submesh), true);
              initialEyeSubmesh = submesh;
          }
          if (submesh.name.matches(".*hair.*") || (submesh.name.matches(".*head.*")) && childShapeMap.containsKey(submesh)) {
              toggleChildVisibility(childShapeMap.get(submesh), true);
          }
          if (submesh.name.matches(".*tail.*") && childShapeMap.containsKey(submesh)) {
              toggleChildVisibility(childShapeMap.get(submesh), true);
          }
      }    
  }

  PShape createSubmeshShape(Submesh submesh) {
      PShape part = createShape();
      part.beginShape(TRIANGLES);
      
      // Assign the correct texture based on the submesh's material index
      if (submesh.material >= 0 && submesh.material < textures.size()) {
          PImage tex = textures.get(submesh.material);
          if (tex != null) {
              part.texture(tex);
          }
      } else {
          println("Warning: Invalid material index " + submesh.material + " for submesh " + submesh.name);
      }
      
      part.textureMode(NORMAL);
      part.noStroke();
  
      for (int idx : submesh.vertexIndices) {
          if (idx < vertices.size() && idx < uvs.size()) {
              PVector v = vertices.get(idx);
              PVector uv = uvs.get(idx);
              part.vertex(v.x, v.y, v.z, uv.x, uv.y);
          }
      }
  
      part.endShape();
      return part;
  }
  
  void selectSet(int newSet) {
      if (availableSets.contains(newSet)) {
          selectedSet = newSet;
          buildMesh();
      } else {
          println("Error: Set " + newSet + " not available.");
      }
  }

void updateMeshVertices() {
    if (mesh == null) return;

    int submeshIndex = 0;
    for (PShape part : mesh.getChildren()) {
        if (submeshIndex >= submeshes.size()) break;
        Submesh submesh = submeshes.get(submeshIndex);

        // Only update vertices if the submesh is visible
        if (submesh.currentVisible || submesh.name.toString().toLowerCase().contains("eyes_")) {
            if (submesh.vertexIndices != null) {
                for (int i = 0; i < submesh.vertexIndices.length; i++) {
                    int originalIndex = submesh.vertexIndices[i];
                    if (originalIndex < skinnedVerts.size()) {
                        PVector v = skinnedVerts.get(originalIndex);
                        part.setVertex(i, v.x, v.y, v.z);
                    }
                }
            }
        }
        submeshIndex++;
    }
}

  void applySkinning() {
  // Initialize skinnedVerts with original vertex positions
  skinnedVerts = new ArrayList<>(vertices.size());
  for (PVector v : vertices) {
      skinnedVerts.add(v.copy());
  }
    
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
             
            //IGNORE THE JAW/MOUTH BONE SO WE CAN MODULATE IT WITH AUDIO :DDDD 
            if (modulateMouth && bone.name.toLowerCase().endsWith("_bn_jaw") || (bone.name.toLowerCase().endsWith("_bn_mouth"))) continue;

            // Use rest pose matrix just once when the model is initially loaded, probably a better way to do this
            PMatrix3D skinningMatrix = (currentAnim == null || startup == true )
                ? bone.restPoseMatrix.get() 
                : bone.animatedMatrix.get();

            // Calculate skinning matrix: Global Transform * Inverse Bind Matrix
            skinningMatrix.apply(bone.inverseBindMatrix);

            boolean hideWings = true;
            if (hideWings) {
            if (bone.name.toLowerCase().contains("_bn_wing")) {
              bone.animatedMatrix.scale(0);
                }
            }

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
    
    if (modulateMouth) modulateMouthBone(); // Apply modulation to jaw/mouth vertices
    
    updateMeshVertices();

    if (startup) {
        startup = false; //dont use rest pose matrix after loading model
    }
  }
  
  void loadVisibilityXML(String xmlPath) {
    visibilityData = parseAnimVisibilityXML(xmlPath, this);
    println("XML PATH:");
    println(xmlPath);
    
    // Initialize submesh visibility
    for (ArrayList<Submesh> submeshes : visibilityData.objectDefinitions.values()) {
      for (Submesh sm : submeshes) {
        sm.currentVisible = sm.defaultVisible;
        toggleSubmeshVisibility(sm, sm.defaultVisible);
      }
    }
  }

  void updateVisibilityForFrame(String animName, int frameDur) {
      if (visibilityData == null) {
          println("Visibility data is null");
          return;
      }
  
      ArrayList<FrameVisibility> frames = visibilityData.animations.get(animName);
      if (frames == null) {
          //println("No frames found for animation: '" + animName + "'");
          return;
      }
  
      // Process current frame's visibility data
      for (FrameVisibility fv : frames) {
          if (fv.frameIndex == frameDur) {
              // If we are about to process an eye state and we still have the initial eye submesh active,
              // then disable it.
              if (fv.eyeState != null && initialEyeSubmesh != null) {
                  println("Disabling initial eye submesh: " + initialEyeSubmesh.name);
                  toggleSubmeshVisibility(initialEyeSubmesh, false);
                  // Clear it out so we dont try to disable it again.
                  initialEyeSubmesh = null;
              }
  
              // Handle eye states first
              if (fv.eyeState != null) {
                  println("Handling eye state for frame: " + frameDur);
                  println("Eye mode: " + fv.eyeState.mode + ", Blink: " + fv.eyeState.blink);
  
                  // Disable previous eye submesh if one was active
                  if (currentEyeSubmesh != null) {
                      println("Hiding previously active eye submesh: " + currentEyeSubmesh.name);
                      toggleSubmeshVisibility(currentEyeSubmesh, false);
                  }
  
                  // Check for CLOSED mode without blinking first
                  if (fv.eyeState.mode.toString().toLowerCase().contains("closed") && !fv.eyeState.blink) {
                      currentEyeMode = "closed";
                      isBlinking = false;
                      String newEyeID = "eyes_shut";
  
                      // Find and enable eyes_closed submesh
                      for (Submesh sm : submeshes) {
                          if (sm.name.toLowerCase().contains(newEyeID)) {
                              println("Showing submesh: " + sm.name);
                              toggleSubmeshVisibility(sm, true);
                              currentEyeSubmesh = sm;
                              break;
                          }
                      }
                  }
                  // Check for "none" mode (interpreted here as open)
                  else if (fv.eyeState.mode.toString().toLowerCase().contains("none") && !fv.eyeState.blink) {
                      currentEyeMode = "closed";
                      isBlinking = false;
                      String newEyeID = "eyes_open";
  
                      // Find and enable eyes_open submesh
                      for (Submesh sm : submeshes) {
                          if (sm.name.toLowerCase().contains(newEyeID)) {
                              println("Showing submesh: " + sm.name);
                              toggleSubmeshVisibility(sm, true);
                              currentEyeSubmesh = sm;
                              break;
                          }
                      }
                  }
                  // Then check for blinking state (applies to all other eye modes)
                  else if (fv.eyeState.blink) {
                      // Start blinking: save current eye mode and trigger blink
                      currentEyeMode = fv.eyeState.mode.toString().toLowerCase();
                      isBlinking = true;
                      blinkCounter = 0; // Reset counter on new blink
                      String newEyeID = "eyes_shut";
  
                      // Find and enable eyes_shut submesh
                      for (Submesh sm : submeshes) {
                          if (sm.name.toLowerCase().contains(newEyeID)) {
                              println("Showing submesh: " + sm.name);
                              toggleSubmeshVisibility(sm, true);
                              currentEyeSubmesh = sm;
                              break;
                          }
                      }
                  } 
                  // Otherwise, use the non-blinking version of the specified eye mode
                  else {
                      currentEyeMode = fv.eyeState.mode.toString().toLowerCase();
                      isBlinking = false;
                      String newEyeID = "eyes_" + currentEyeMode;
  
                      // Find and enable new eye submesh
                      for (Submesh sm : submeshes) {
                          if (sm.name.toLowerCase().contains(newEyeID)) {
                              println("Showing submesh: " + sm.name);
                              toggleSubmeshVisibility(sm, true);
                              currentEyeSubmesh = sm;
                              break;
                          }
                      }
                  }
              } else {
                  println("No eye state for frame: " + frameDur);
              }
  
              // Handle regular submesh visibility (non-eye)
              for (Map.Entry<String, Boolean> entry : fv.submeshVisibility.entrySet()) {
                  String xmlID = entry.getKey();
                  boolean visible = entry.getValue();
                  println("Processing regular submesh: " + xmlID + ", Visible: " + visible);
  
                  for (Submesh sm : submeshes) {
                      if (sm.name.toLowerCase().equals(xmlID.toLowerCase())) {
                          toggleSubmeshVisibility(sm, visible);
                          println("Toggling visibility of submesh " + sm.name + ": " + visible);
                      }
                  }
              }
              break; // Found our matching frame so break out of the loop.
          }
      }
  
      // Handle blinking state progression regardless of current frame's eye state
      if (isBlinking) {
          blinkCounter++;
          println("Blinking, counter: " + blinkCounter);
          if (blinkCounter >= blinkDuration) {
              println("Reverting to eye mode: " + currentEyeMode);
              String revertEyeID = "eyes_" + currentEyeMode;
  
              // Disable current eye submesh (eyes_shut)
              if (currentEyeSubmesh != null) {
                  toggleSubmeshVisibility(currentEyeSubmesh, false);
              }
  
              // Find and enable the original eye submesh
              for (Submesh sm : submeshes) {
                  if (sm.name.toLowerCase().contains(revertEyeID)) {
                      println("Showing reverted submesh: " + sm.name);
                      toggleSubmeshVisibility(sm, true);
                      currentEyeSubmesh = sm;
                      break;
                  }
              }
  
              // Reset blinking state
              isBlinking = false;
              blinkCounter = 0;
          }
      }
  }

  void toggleSubmeshVisibility(Submesh sm, boolean visible) { 
      sm.currentVisible = visible;
      if (childShapeMap.containsKey(sm)) {
          PShape child = childShapeMap.get(sm);
          toggleChildVisibility(child, visible);
      }
  }
  
  void toggleChildVisibility(PShape shape, boolean show) {
      if (shape == null) return;
      if (show) {
          shape.resetMatrix(); // Reset to original state
      } else {
          shape.scale(0); // Hide by scaling to zero
      }
  }



  void printSummary() {
    println("\nModel Summary:");
    println("Vertices: " + vertices.size());
    println("Triangles: " + triangles.size());
    println("Bones: " + bones.size());
    println("Materials: " + materials.size());
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
  

  PShape renderSubmesh(int submeshIndex) {
      if (submeshIndex < 0 || submeshIndex >= submeshes.size()) {
          println("Error: Invalid submesh index");
          return null;
      }
  
      Submesh submesh = submeshes.get(submeshIndex);
      PShape part = createShape();
      part.beginShape(TRIANGLES);

      // Assign the correct texture based on the submesh's material index
      if (submesh.material >= 0 && submesh.material < textures.size()) {
          PImage tex = textures.get(submesh.material);
          if (tex != null) {
              part.texture(tex);
          }
      } else {
          println("Warning: Invalid material index " + submesh.material + " for submesh " + submesh.name);
      }
      
      part.textureMode(NORMAL);
      part.noStroke();
  
      for (int[] tri : submesh.triangles) {
          for (int index : tri) {
              if (index >= vertices.size()) {
                  println("Error: Invalid vertex index", index);
                  continue;
              }
              PVector v = vertices.get(index);
              PVector uv = uvs.get(index);
              part.vertex(v.x, v.y, v.z, uv.x, uv.y);
          }
      }
      part.endShape();
      return part;
  }


  void draw() {
    updateAnimation();
    shape(mesh);
    
    /*
    // Render only the second submesh (index 1)
    PShape submeshShape = renderSubmesh(1); // Change index to test other submeshes
    if (submeshShape != null) {
        shape(submeshShape);
    } //
    */
  }
}
