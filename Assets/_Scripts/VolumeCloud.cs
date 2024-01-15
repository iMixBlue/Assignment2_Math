using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumeCloud : ScriptableRendererFeature
{

    [System.Serializable]
    public class Setting
    {
        //Post processing material
        public Material CloudMaterial;
        //Render Queue
        public RenderPassEvent RenderQueue = RenderPassEvent.AfterRenderingSkybox;
        //Render Texture scale (Cloud)
        [Range(0.1f, 1)]
        public float RTScale = 0.5f;

    }


    class VolumeCloudRenderPass : ScriptableRenderPass
    {
        public Setting Set;
        public string name;
        public RenderTargetIdentifier cameraColorTex;
        //Clout render texture width
        public int width;
        //Clout render texture height
        public int height;


        public VolumeCloudRenderPass(Setting set, string name)
        {
            renderPassEvent = set.RenderQueue;
            this.Set = set;
            this.name = name;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(name);

                //create tempory render texture
                RenderTextureDescriptor temDescriptor = new RenderTextureDescriptor(width, height, RenderTextureFormat.ARGB32);
                // temDescriptor.depthBufferBits = 0;
                // int temTextureID = Shader.PropertyToID("_CloudTex");
                int temTextureID = Shader.PropertyToID("_CloudTex");

                cmd.SetGlobalTexture("_MainTex", cameraColorTex);
                
                cmd.GetTemporaryRT(temTextureID, temDescriptor);


                cmd.Blit(cameraColorTex, temTextureID,Set.CloudMaterial,0);
                cmd.Blit(temTextureID, cameraColorTex,Set.CloudMaterial,1);

                //execute
                context.ExecuteCommandBuffer(cmd);
                //release RT
                cmd.ReleaseTemporaryRT(temTextureID);
                //release RT
                CommandBufferPool.Release(cmd);
        }

    }

    VolumeCloudRenderPass cloudPass;
    public Setting Set = new Setting();

    public override void Create()
    {
        cloudPass = new VolumeCloudRenderPass(Set, name);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        //Cloud render texture resolution
        int width = (int)(renderingData.cameraData.cameraTargetDescriptor.width * Set.RTScale);
        int height = (int)(renderingData.cameraData.cameraTargetDescriptor.height * Set.RTScale);

        cloudPass.width = width;
        cloudPass.height = height;
        renderer.EnqueuePass(cloudPass);
    }
    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        cloudPass.cameraColorTex = renderer.cameraColorTargetHandle;
    }


}


