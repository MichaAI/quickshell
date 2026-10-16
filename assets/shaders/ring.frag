#version 440
// Волнистое кольцо, как CircularWavyProgressIndicator из MD3 Expressive:
// активная дуга — волна по радиусу, остаток — ровная дорожка с зазорами
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float progress;     // 0..1
    float amp;          // px
    float wavelength;   // px по окружности
    float phase;        // в длинах волны
    float thick;
    float gap;          // px между концами дуг
    vec4 c0;
    vec4 c1;
    vec4 track;
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


// Доля оборота от 12 часов по часовой стрелке
float turn(vec2 d) {
    return fract(atan(d.x, -d.y) / TAU + 1.0);
}

void main() {
    vec2 c = size * 0.5;
    vec2 p = qt_TexCoord0 * size - c;
    float R = min(size.x, size.y) * 0.5 - thick * 0.5 - amp - 1.0;
    float circ = TAU * R;
    float waves = max(1.0, floor(circ / wavelength + 0.5));
    float cap = thick * 0.5 / circ;          // полтолщины в долях оборота
    float gapA = gap / circ;
    float a = turn(p);
    float rho = length(p);

    float r = thick * 0.5;
    // Под конец концы дуги сходятся и срастаются в целое кольцо: иначе
    // наверху остаётся щербина между двумя скруглёнными концами
    float close = smoothstep(0.995, 1.0, progress);
    // Активная дуга: центр линии от cap до progress - cap
    float a0 = cap * (1.0 - close), a1 = progress - cap * (1.0 - close);
    float act = 0.0;
    if (a1 > a0) {
        float d;
        if (a >= a0 && a <= a1) {
            float s = TAU * (waves * a - phase);
            float rr = R + amp * sin(s);
            float slope = amp * waves / R * cos(s);
            d = abs(rho - rr) / sqrt(1.0 + slope * slope);
        } else {
            vec2 e0 = (R + amp * sin(TAU * (waves * a0 - phase))) * vec2(sin(TAU * a0), -cos(TAU * a0));
            vec2 e1 = (R + amp * sin(TAU * (waves * a1 - phase))) * vec2(sin(TAU * a1), -cos(TAU * a1));
            d = min(distance(p, e0), distance(p, e1));
        }
        act = clamp(r - d + 0.5, 0.0, 1.0);
    }
    // Дорожка: от progress + зазор до 1 - зазор
    float t0 = progress + gapA + cap, t1 = 1.0 - gapA - cap;
    if (progress <= 0.0) { t0 = cap; t1 = 1.0 - cap; }
    float trk = 0.0;
    if (t1 > t0) {
        float d;
        if (a >= t0 && a <= t1) d = abs(rho - R);
        else {
            vec2 e0 = R * vec2(sin(TAU * t0), -cos(TAU * t0));
            vec2 e1 = R * vec2(sin(TAU * t1), -cos(TAU * t1));
            d = min(distance(p, e0), distance(p, e1));
        }
        trk = clamp(r - d + 0.5, 0.0, 1.0);
    }

    // Цвет — от начала дуги к её концу; у полного кольца конец упёрся бы
    // в начало резким стыком, поэтому к 100% градиент становится зеркальным:
    // наверху начальный цвет, внизу конечный
    float t = clamp((a - a0) / max(a1 - a0, 0.001), 0.0, 1.0);
    t = mix(t, 1.0 - abs(2.0 * a - 1.0), smoothstep(0.85, 1.0, progress));
    vec3 col = fromOklab(mix(oklab(c0.rgb), oklab(c1.rgb), t));
    vec4 o = track * trk;
    o = vec4(col, 1.0) * act + o * (1.0 - act);
    fragColor = o * qt_Opacity;
}
