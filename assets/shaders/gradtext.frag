#version 440
// Градиентный текст (components/GradientText.qml): текст отрисован белым в
// текстуру source, тут его альфа красится градиентом c0 → c1 по
// горизонтали, смешанным в OkLab, как Theme.mix. Под ним — обводка
// цвета oc: альфа текста, сдвинутая по окружности радиуса outline
// (steps выборок) — те же копии, что раньше были отдельными Text.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // размер текстуры в пикселях (с запасом по краям)
    float x0;           // где градиент ещё c0, px от левого края текстуры
    float span;         // на скольких px он доходит до c1
    float outline;      // радиус обводки, px; 0 — без неё
    float steps;
    vec4 c0;
    vec4 c1;
    vec4 oc;
};

layout(binding = 1) uniform sampler2D source;

const float TAU = 6.28318530718;

vec3 toLinear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 toSrgb(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

vec3 oklab(vec3 c) {
    vec3 l = toLinear(c);
    vec3 lms = pow(max(vec3(dot(l, vec3(0.4122214708, 0.5363325363, 0.0514459929)),
                            dot(l, vec3(0.2119034982, 0.6806995451, 0.1073969566)),
                            dot(l, vec3(0.0883024619, 0.2817188376, 0.6299787005))), 0.0),
                   vec3(1.0 / 3.0));
    return vec3(dot(lms, vec3(0.2104542553, 0.7936177850, -0.0040720468)),
                dot(lms, vec3(1.9779984951, -2.4285922050, 0.4505937099)),
                dot(lms, vec3(0.0259040371, 0.7827717662, -0.8086757660)));
}

vec3 fromOklab(vec3 c) {
    vec3 lms = vec3(dot(c, vec3(1.0, 0.3963377774, 0.2158037573)),
                    dot(c, vec3(1.0, -0.1055613458, -0.0638541728)),
                    dot(c, vec3(1.0, -0.0894841775, -1.2914855480)));
    lms = lms * lms * lms;
    return toSrgb(vec3(dot(lms, vec3(4.0767416621, -3.3077115913, 0.2309699292)),
                       dot(lms, vec3(-1.2684380046, 2.6097574011, -0.3413193965)),
                       dot(lms, vec3(-0.0041960863, -0.7034186147, 1.7076147010))));
}

void main() {
    float a = texture(source, qt_TexCoord0).a;

    float t = span > 0.0 ? clamp((qt_TexCoord0.x * size.x - x0) / span, 0.0, 1.0) : 0.0;
    vec3 g = fromOklab(mix(oklab(c0.rgb), oklab(c1.rgb), t));
    vec4 col = vec4(g, 1.0) * a;

    if (outline > 0.0) {
        float o = 0.0;
        int n = int(steps);
        for (int k = 0; k < 24; k++) {
            if (k >= n)
                break;
            float ang = float(k) * TAU / steps;
            vec2 d = vec2(cos(ang), sin(ang)) * outline / size;
            o = max(o, texture(source, qt_TexCoord0 + d).a);
        }
        // Обводка — под текстом
        col += vec4(oc.rgb, 1.0) * oc.a * o * (1.0 - a);
    }

    fragColor = col * qt_Opacity;
}
