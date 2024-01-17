using System;
using System.Runtime.InteropServices;


namespace Daxode.UnityInterfaceBridge
{    
    public static class OdecsUnityBridge {
        [DllImport("odecs_unitybridge")]
        public static extern IntPtr GetDefaultOdecsContext();    
    }
}