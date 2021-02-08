using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace GC
{
    public enum ColorMode
    {
        RAW_IMG = 0,
        ONLY_AO,
        WITH_AO,
    }
    public class AO : MonoBehaviour
    {
        public Material mat;
        public Texture2D NoiseDebug;

        [Header("AO Sample Kernel")]
        [Range(4, 64)]
        public int KernelSize = 64;
        [Range(0, 1f)]
        public float Bias;
        [Range(0, 1f)]
        public float Radius;

        [Header("Random Noise")]
        public int NoiseSize = 4;

        [Header("Debug")]
        public ColorMode Mode = ColorMode.RAW_IMG;


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

        public void UpdateMat()
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
            switch (Mode)
            {
                case ColorMode.ONLY_AO:
                    mat.EnableKeyword("_ONLY_AO");
                    mat.DisableKeyword("_RAW_IMG");
                    mat.DisableKeyword("_WITH_AO");
                    break;
                case ColorMode.RAW_IMG:
                    mat.EnableKeyword("_RAW_IMG");
                    mat.DisableKeyword("_ONLY_AO");
                    mat.DisableKeyword("_WITH_AO");
                    break;
                case ColorMode.WITH_AO:
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
            mat.SetMatrix("projection", Camera.main.projectionMatrix);

            RenderTexture rt = RenderTexture.GetTemporary(Screen.width / 2, Screen.height / 2);
            Graphics.Blit(source, rt, mat, 0);
            mat.SetTexture("_AOTex", rt);
            Graphics.Blit(source, destination, mat, 1);
            RenderTexture.ReleaseTemporary(rt);
        }
    }
}
