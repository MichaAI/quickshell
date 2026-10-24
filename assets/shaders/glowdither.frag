#version 440
// Дизеринг мягкого света перед выводом в 8 бит: к цвету и прозрачности —
// шум с треугольным распределением в ±amount уровней. Ступени размытия
// (8-битные слои, 8-битный экран) на глаз сливаются, а зерна не видно.
// Шум привязан к пикселям экрана и не мерцает. Где света нет — пусто:
// иначе шум лёг бы на весь шелл.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float amount;       // в уровнях из 255
};

layout(binding = 1) uniform sampler2D source;

// Хеш без синусов (Dave Hoskins, «Hash without Sine»)
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Треугольный шум в (-1, 1): сумма двух равномерных
float tri(vec2 p) {
    return hash(p) + hash(p + vec2(17.31, 41.17)) - 1.0;
}

void main() {
    vec4 c = texture(source, qt_TexCoord0);    // premultiplied
    if (c.a < 0.5 / 255.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec2 px = floor(gl_FragCoord.xy);
    float k = amount / 255.0;
    float a = clamp(c.a + tri(px + vec2(91.7, 13.3)) * k, 0.0, 1.0);
    vec3 rgb = clamp(c.rgb + tri(px) * k, 0.0, a);
    fragColor = vec4(rgb, a) * qt_Opacity;
}
