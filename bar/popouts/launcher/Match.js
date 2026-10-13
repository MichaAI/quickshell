.pragma library

// Оценка совпадения: начало > начало слова > подстрока > подпоследовательность
function score(text, q) {
    if (q === "") return 1
    const t = (text ?? "").toLowerCase()
    if (t.startsWith(q)) return 100
    if (t.includes(" " + q) || t.includes("-" + q) || t.includes("." + q)) return 80
    if (t.includes(q)) return 60
    let i = 0
    for (const ch of t)
        if (ch === q[i]) i++
    return i === q.length ? 10 : 0
}

function filterBy(list, q, fields) {
    const lq = q.toLowerCase()
    // Индекс — чтобы при равных очках сохранялся исходный порядок
    return list
        .map((x, i) => [Math.max(...fields(x).map(f => score(f, lq))), x, i])
        .filter(x => x[0] > 0)
        .sort((a, b) => b[0] - a[0] || a[2] - b[2])
        .map(x => x[1])
}
