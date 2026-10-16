#version 440
// Фигура MD3 Expressive с морфингом. Форма — радиус от угла: лепестки
// (n, глубина k) поверх суперэллипса (степень p, вытянутость aspect по x).
// Морф — смесь радиусов двух форм; box подмешивает скруглённый
// прямоугольник (через поле расстояний), band истончает заливку до обводки.
// Вокруг — рамка outline цвета фона, чтобы отделить фигуру от того, что под ней.
// reveal — видно только внутри круга (x, y от центра, радиус), если w > 0.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 shapeA;        // n, k, p, aspect
    vec4 shapeB;
    float morph;        // 0 — shapeA, 1 — shapeB
    float turn;         // поворот, в оборотах
    float radius;       // px, самый дальний край формы
    vec4 box;           // полуширина, полувысота, радиус углов, доля прямоугольника
    float band;         // толщина заливки от края внутрь, px; большое — сплошная
    float outline;      // рамка снаружи, px
    vec4 outlineColor;
    vec4 c0;
    vec4 c1;
    vec4 reveal;
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


float polar(vec4 s, float th) {
    float x = abs(cos(th)) / s.w, y = abs(sin(th));
    float se = pow(pow(x, s.z) + pow(y, s.z), -1.0 / s.z) / max(s.w, 1.0);
    float lobes = 1.0 - s.y + s.y * cos(s.x * th);
    return se * lobes;
}

float shapeR(float th) {
    return radius * mix(polar(shapeA, th), polar(shapeB, th), morph);
}

float roundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * size - size * 0.5;
    float rho = length(p);
    float th = atan(p.y, p.x) - TAU * turn;

    // Расстояние до края: по радиусу, с поправкой на наклон края
    float r = shapeR(th);
    float dr = (shapeR(th + 0.002) - shapeR(th - 0.002)) / 0.004;
    float dPolar = (rho - r) / sqrt(1.0 + dr * dr / max(rho * rho, 1.0));
    float d = mix(dPolar, roundBox(p, box.xy, box.z), box.w);

    float fill = clamp(0.5 - d, 0.0, 1.0) * clamp(0.5 + d + band, 0.0, 1.0);
    float ring = clamp(0.5 - d + outline, 0.0, 1.0) * (1.0 - clamp(0.5 - d, 0.0, 1.0));

    float span = mix(radius, box.x, box.w);
    float t = clamp((p.x + span) / max(2.0 * span, 1.0), 0.0, 1.0);
    vec3 col = fromOklab(mix(oklab(c0.rgb), oklab(c1.rgb), t));
    vec4 o = outlineColor * ring * step(0.01, outline);
    o = vec4(col, 1.0) * fill + o * (1.0 - fill);
    if (reveal.w > 0.0)
        o *= clamp(reveal.z - distance(p, reveal.xy) + 0.5, 0.0, 1.0);
    fragColor = o * qt_Opacity;
}
