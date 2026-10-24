#version 440
// Волна активной части слайдера, как у LinearWavyProgressIndicator из MD3
// Expressive: синусоида толщиной thick со скруглёнными концами. Цвет —
// градиент c0 → c1 по длине, смешанный в OkLab, как Theme.mix.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float amp;          // амплитуда, px
    float wavelength;   // px
    float phase;        // сдвиг волны в длинах волны
    float thick;
    vec4 c0;
    vec4 c1;
};

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

float wave(float x) {
    return size.y * 0.5 + amp * sin(TAU * (x / wavelength - phase));
}

float slopeAt(float x) {
    return amp * TAU / wavelength * cos(TAU * (x / wavelength - phase));
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float r = thick * 0.5;
    // Полпикселя от краёв — на сглаживание шапок, иначе его режет край
    float x0 = r + 0.5, x1 = size.x - r - 0.5;

    // Концы: шапка — круг в конце кривой; тело кончается перпендикуляром
    // к ней, а не вертикалью — иначе на наклоне край тела торчит из шапки
    // острым углом
    vec2 e0 = vec2(x0, wave(x0)), e1 = vec2(x1, wave(x1));
    vec2 t0 = normalize(vec2(1.0, slopeAt(x0)));
    vec2 t1 = normalize(vec2(1.0, slopeAt(x1)));

    // Расстояние до кривой: по вертикали, поправленное на наклон, а за
    // концами — до центра шапки
    float d;
    if (dot(p - e0, t0) < 0.0)
        d = distance(p, e0);
    else if (dot(p - e1, t1) > 0.0)
        d = distance(p, e1);
    else {
        float slope = slopeAt(clamp(p.x, x0, x1));
        d = abs(p.y - wave(clamp(p.x, x0, x1))) / sqrt(1.0 + slope * slope);
    }
    float a = clamp(r - d + 0.5, 0.0, 1.0);

    float t = clamp((p.x - x0) / max(x1 - x0, 1.0), 0.0, 1.0);
    vec3 c = fromOklab(mix(oklab(c0.rgb), oklab(c1.rgb), t));
    fragColor = vec4(c, 1.0) * a * qt_Opacity;
}
