using UnityEngine;
using UnityEditor;

namespace GC
{
    [CustomEditor(typeof(AO))]
    public class AOEditior : Editor
    {
        public override void OnInspectorGUI()
        {
            EditorGUI.BeginChangeCheck();
            base.OnInspectorGUI();
            if(EditorGUI.EndChangeCheck())
            {
                AO ao = target as AO;
                ao.UpdateMat();
            }
        }
    }

}