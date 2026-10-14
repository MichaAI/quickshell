#version 440
// Крупнозернистый упорядоченный дизеринг (Байер 4×4) в палитру из 4 цветов.
// Картинка режется на клетки по pixel пикселей, яркость клетки + порог Байера
// выбирают цвет палитры. Прозрачность — тоже через порог, без полутонов.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float pixel;
    vec4 c0;
    vec4 c1;
    vec4 c2;
    vec4 c3;
};

layout(binding = 1) uniform sampler2D source;

const float bayer[16] = float[16](
     0.0,  8.0,  2.0, 10.0,
    12.0,  4.0, 14.0,  6.0,
     3.0, 11.0,  1.0,  9.0,
    15.0,  7.0, 13.0,  5.0);

void main() {
    vec2 cell = floor(qt_TexCoord0 * size / pixel);
    vec2 uv = (cell + 0.5) * pixel / size;
    vec4 s = texture(source, uv);

    ivec2 b = ivec2(mod(cell, 4.0));
    float t = (bayer[b.y * 4 + b.x] + 0.5) / 16.0;

    if (s.a < t) {
        fragColor = vec4(0.0);
        return;
    }
    vec3 rgb = s.rgb / max(s.a, 0.001);
    float l = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    // 4 уровня: порог сдвигает границу между соседними цветами
    float idx = clamp(floor(l * 3.0 + t), 0.0, 3.0);
    vec4 c = idx < 0.5 ? c0 : idx < 1.5 ? c1 : idx < 2.5 ? c2 : c3;
    fragColor = vec4(c.rgb, 1.0) * qt_Opacity;
}
