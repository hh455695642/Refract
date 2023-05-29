Shader "Unlit/Refract"
{
    Properties
    {
        [MaiColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 0.5)
        [MaiTexture] _BaseMap ("Base Map", 2D) = "white" { }
        [Normal] _NormalMap ("Normal Map", 2D) = "bump" { }
        _NormalStrength ("Normal Strength", float) = 0.1
        _IOR_above ("IOR above", float) = 1
        _IOR_below ("IOR below", float) = 1.33
    }

    SubShader
    {
        
        Tags { "RenderType" = "Transparent" "RenderPipelie" = "UniversalPipelie" "Queue" = "Transparent"  }
        

        Pass
        {
            
            Name "ForwardUnlit"

            ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha
            
            HLSLPROGRAM
            
            #pragma vertex vert            
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
  
            struct Attributes
            {              
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            struct Varyigs
            {           
                float4 positionHCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 positionVS : TEXCOORD1;
                float4 positionNDC : TEXCOORD6;
                float2 uv : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
                float3 tangentWS : TEXCOORD4;
                float3 bitangentWS : TEXCOORD5;
                float3 scale : TEXCOORD7;
            };
            
            TEXTURE2D(_BaseMap);          SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);          SAMPLER(sampler_NormalMap);
            TEXTURE2D_X(_CameraOpaqueTexture);          

            CBUFFER_START(UnityPerMaterial)               
                half4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _NormalMap_ST;
                float _NormalStrength,_IOR_above,_IOR_below;
            CBUFFER_END
            
            Varyigs vert(Attributes v)
            {
               
                Varyigs o;
            
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionHCS = vertexInput.positionCS;
                o.positionWS = vertexInput.positionWS;
                o.positionVS = vertexInput.positionVS;
                o.positionNDC = vertexInput.positionNDC;

                VertexNormalInputs vertexNormalInputs = GetVertexNormalInputs(v.normalOS,v.tangentOS);
                o.normalWS = vertexNormalInputs.normalWS;               
                o.bitangentWS= vertexNormalInputs.bitangentWS;
                o.tangentWS = vertexNormalInputs.tangentWS;
                
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);

                float3 scale;
                float4x4 MV = mul(UNITY_MATRIX_V, UNITY_MATRIX_M);
                scale.x = length(float3(MV[0].x, MV[1].x, MV[2].x));
                scale.y = length(float3(MV[0].y, MV[1].y, MV[2].y));
                scale.z = length(float3(MV[0].z, MV[1].z, MV[2].z));
                o.scale = max(scale.x, max(scale.y, scale.z));
                
                return o;
            }

            // From Walter 2007 eq. 40
            // Expects incoming pointing AWAY from the surface
            // eta = IOR_above / IOR_below 折射指数(两个介质之间的折射率比) 它描述了光在该物质中传播时的速度变化。折射指数通常是一个大于1的值，表示光线从第一个介质（例如空气）射入第二个介质（例如玻璃）时的相对速度变化。
            // rayIntensity returns 0 in case of total internal reflection  在全内反射的情况下，rayIntensity返回0
            //
            // Walter et al. formula seems to have a typo in it: the b term below needs to have eta^2 instead of eta. 
            // Walter等人的公式中似乎有一个拼写错误：下面的b项需要有eta^2而不是eta。
            // Note also that our sign(c) term here effectively makes the refractive
            // surface dual sided.

            void Unity_RefractCriticalAngle(float3 Incident, float3 Normal, float IORInput, float IORMedium, out float3 Refracted)
            {
                float internalIORInput = max(IORInput, 1.0);
                float internalIORMedium = max(IORMedium, 1.0);
                float eta = internalIORInput / internalIORMedium;
                float cos0 = dot(Incident, Normal);
                float k = 1.0 - eta * eta * (1.0 - cos0 * cos0);
                Refracted = k >= 0.0 ? eta * Incident - (eta * cos0 + sqrt(k)) * Normal : reflect(Incident, Normal);
            }

            half4 frag(Varyigs i) : SV_Target
            {
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half3 lightDir = mainLight.direction;

                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                
                half3 NormalMap = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv), _NormalStrength) ;
                
                //世界空间法线贴图
                half3x3 tangentToWorld = half3x3(i.tangentWS.xyz, i.bitangentWS, i.normalWS.xyz);
                half3 normalWS = normalize(TransformTangentToWorld(NormalMap, tangentToWorld)) ;

                //方法一：
                // float3 refractWS;
                // Unity_RefractCriticalAngle(-viewDirWS, normalWS, _IOR_above, _IOR_below, refractWS);

                // float3 refractDir = normalize(TransformWorldToTangent(refractWS, tangentToWorld));

                // float3 screenUV = i.positionHCS.xyz / _ScreenParams;
                // screenUV = (screenUV + refractDir) - floor(screenUV + refractDir);

                //方法二：
                float3 refractWS;
                Unity_RefractCriticalAngle(-viewDirWS, normalWS, _IOR_above, _IOR_below, refractWS);

                half rayLength = -dot(i.normalWS, refractWS);
                float3 rayOriginWS = i.positionWS + (refractWS * rayLength);
                float3 refractedPointWS = rayOriginWS + (refractWS * i.scale);

                float4 screenUV = TransformWorldToHClip(refractedPointWS);
                screenUV.xyz = screenUV.xyz / screenUV.w;
                #if UNITY_UV_STARTS_AT_TOP
                    screenUV.y = -screenUV.y;
                #endif
                screenUV.xy = screenUV.xy * 0.5f + 0.5f;

                half4 OpaqueTex = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_LinearClamp, screenUV.xy);
                return half4(OpaqueTex.xyz, _BaseColor.a);
            }
            ENDHLSL
        }
    }
}
