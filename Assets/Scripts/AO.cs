using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace GC
{
    public enum OutputMode
    {
        RAW_IMG = 0,
        ONLY_AO,
        WITH_AO,
    }
    public enum AOMODE
    {
        SSAO = 0,
        HBAO,
        GTAO,
    }
    public class AO : MonoBehaviour
    {
        public AOMODE AOMode;
        public Texture2D NoiseDebug;

        [Header("SSAO Sample Kernel")]
        [Range(4, 64)]
        public int KernelSize = 64;
        [Range(0, 1f)]
        public float Bias;
        [Range(0, 1f)]
        public float Radius;

        [Header("SSAO Random Noise")]
        public int NoiseSize = 4;

        [Header("GTAO")]
        public int MarchingCount = 20;
        public int SliceCount = 1;
        public float GTAO_Radius = 1.0f;

        [Header("HBAO")]
        public int HBAO_MarchingCount = 20;
        public int HBAO_SliceCount = 1;
        public float HBAO_Radius = 1.0f;
        public float HBAO_Bias = 0.1f;
        public float AOStrength = 1.9f;
        public float MaxRadiusPixels = 59.0f;
        public bool UseMyImpl = false;

        [Header("Debug")]
        public OutputMode TexMode = OutputMode.RAW_IMG;

        private Material mat;

        // Start is called before the first frame update
        void Start()
        {
            GetComponent<Camera>().depthTextureMode = DepthTextureMode.DepthNormals;
            InitKernel();
        }

        void InitKernel()
        {

            UpdateMat();
        }

        private void UpdateSSAOMat()
        {
            mat = new Material(Shader.Find("GC/SSAO"));
            mat.SetInt("kernel_size", KernelSize);
            Random.InitState((int)System.DateTimeOffset.Now.ToUnixTimeSeconds());

            List<Vector4> kernelData = new List<Vector4>();
            for (int i = 0; i < KernelSize; i++)
            {
                var v = new Vector4(Random.value * 2.0f - 1.0f, Random.value * 2.0f - 1.0f, Random.value, 0f);
                var dir = v.normalized;
                dir *= Random.value;

                float scale = i / 64.0f;
                scale = Mathf.Lerp(0.1f, 1.0f, scale * scale);
                dir *= scale;
                kernelData.Add(dir);
            }

            mat.SetVectorArray("kernel", kernelData);

            Texture2D tex = new Texture2D(NoiseSize, NoiseSize, TextureFormat.ARGB32, false, true);
            int noiseDataLengh = NoiseSize * NoiseSize;
            Color[] noises = new Color[noiseDataLengh];
            for (int i = 0; i < noiseDataLengh; i++)
            {
                noises[i] = new Color(Random.value, Random.value, Random.value);
            }
            tex.SetPixels(noises);
            tex.wrapMode = TextureWrapMode.Repeat;
            tex.filterMode = FilterMode.Bilinear;
            tex.Apply();

            mat.SetTexture("_NoiseTex", tex);
            NoiseDebug = tex;
            mat.SetFloat("noiseSize", NoiseSize);

            mat.SetFloat("bias", Bias);
            mat.SetFloat("radius", Radius);
        }

        private void UpdateHBAOMat()
        {
            mat = new Material(Shader.Find("GC/HBAO"));
            mat.SetInt("NumSamples", HBAO_MarchingCount);
            mat.SetInt("NumDirections", HBAO_SliceCount);
            mat.SetFloat("_radius", HBAO_Radius);
            mat.SetFloat("_bias", HBAO_Bias);
            mat.SetFloat("AOStrength", AOStrength);
            mat.SetFloat("MaxRadiusPixels", MaxRadiusPixels);
            UpdateUVToView(mat);
        }

        private void UpdateUVToView(Material mat)
        {
            float fovRad = Camera.main.fieldOfView * Mathf.Deg2Rad;
            float invHalfTanFov = 1 / Mathf.Tan(fovRad * 0.5f);
            Vector2 focalLen = new Vector2(invHalfTanFov * (((float)Screen.height) / ((float)Screen.width)), invHalfTanFov);
            Vector2 invFocalLen = new Vector2(1 / focalLen.x, 1 / focalLen.y);
            mat.SetVector("_SSAO_UVToView", new Vector4(2 * invFocalLen.x, 2 * invFocalLen.y, -1 * invFocalLen.x, -1 * invFocalLen.y));
        }

        private void UpdateGTAOMat()
        {
            mat = new Material(Shader.Find("GC/GTAO"));
            mat.SetInt("_marchingCount", MarchingCount);
            mat.SetInt("_scliceCount", SliceCount);
            mat.SetFloat("_radius", GTAO_Radius);
            UpdateUVToView(mat);

            float projScale = (float)Screen.height  / (Mathf.Tan(Camera.main.fieldOfView * Mathf.Deg2Rad * 0.5f) * 2) * 0.5f;
            mat.SetFloat("_SSAO_HalfProjScale", projScale);
        }

        public void UpdateMat()
        {
            switch(AOMode)
            {
                case AOMODE.GTAO:
                    UpdateGTAOMat();
                    break;
                case AOMODE.HBAO:
                    UpdateHBAOMat();
                    break;
                case AOMODE.SSAO:
                    UpdateSSAOMat();
                    break;
            }
            switch (TexMode)
            {
                case OutputMode.ONLY_AO:
                    mat.EnableKeyword("_ONLY_AO");
                    mat.DisableKeyword("_RAW_IMG");
                    mat.DisableKeyword("_WITH_AO");
                    break;
                case OutputMode.RAW_IMG:
                    mat.EnableKeyword("_RAW_IMG");
                    mat.DisableKeyword("_ONLY_AO");
                    mat.DisableKeyword("_WITH_AO");
                    break;
                case OutputMode.WITH_AO:
                    mat.EnableKeyword("_WITH_AO");
                    mat.DisableKeyword("_ONLY_AO");
                    mat.DisableKeyword("_RAW_IMG");
                    break;
            }
        }

        // Update is called once per frame
        void Update()
        {
        }

        private void OnRenderImage(RenderTexture source, RenderTexture destination)
        {
            mat.SetMatrix("invproj", Camera.main.projectionMatrix.inverse);
            switch (AOMode)
            {
                case AOMODE.GTAO:
                    RenderGTAO(source, destination);
                    break;
                case AOMODE.HBAO:
                    RenderHBAO(source, destination);
                    break;
                case AOMODE.SSAO:
                    RenderSSAO(source, destination);
                    break;
            }
        }

        private void RenderGTAO(RenderTexture source, RenderTexture destination)
        {
            Graphics.Blit(source, destination, mat);
        }

        private void RenderHBAO(RenderTexture source, RenderTexture destination)
        {
            Graphics.Blit(source, destination, mat, UseMyImpl ? 1 : 0);
        }

        private void RenderSSAO(RenderTexture source, RenderTexture destination)
        {
            mat.SetMatrix("projection", Camera.main.projectionMatrix);
            RenderTexture rt = RenderTexture.GetTemporary(Screen.width / 2, Screen.height / 2);
            Graphics.Blit(source, rt, mat, 0);
            mat.SetTexture("_AOTex", rt);
            Graphics.Blit(source, destination, mat, 1);
            RenderTexture.ReleaseTemporary(rt);

        }
    }
}
