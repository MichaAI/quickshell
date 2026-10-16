.pragma library

// Формы MD3 Expressive (MaterialShapes) для MorphShape — приближённо:
// [лепестков, глубина лепестка, степень суперэллипса, вытянутость по x]
const circle = [0, 0, 2, 1]
const cookie9 = [9, 0.07, 2, 1]
const cookie4 = [4, 0.1, 2, 1]
const softBurst = [10, 0.09, 2, 1]
const sunny = [8, 0.05, 2, 1]
// Sunny во весь рост, как в MaterialShapes: внутренний радиус 0.8 —
// для солнца в погоде (в цикле лоадера — мягче, выше)
const sunnyFull = [8, 0.1, 2, 1]
const pentagon = [5, 0.08, 2, 1]
const pill = [0, 0, 3.5, 1.45]
const oval = [0, 0, 2, 1.3]

// Цикл M3E LoadingIndicator
const loading = [softBurst, cookie9, pentagon, pill, sunny, cookie4, oval]

// Капля — круг, чуть вытянутый по вертикали
const drop = [0, 0, 2, 0.8]
