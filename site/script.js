(function () {
  const THEMES = [
    ["space", "🚀 Space Station"], ["kitchen", "🍳 Restaurant Kitchen"], ["prison", "⛓️ Prison"],
    ["football", "⚽ Football Match"], ["farm", "🐑 Sheep Farm"], ["impostor", "🕵️ Sneaky Ship"],
    ["wizard", "🪄 Spell Academy"], ["galactic", "🛸 Galactic Fleet"], ["fellowship", "🏔️ Hillside Quest"],
  ];
  const SHOTS = [
    ["live-light", "Live"], ["insights-light", "Insights"], ["history-light", "History"], ["awards-light", "Awards"],
    ["details-light", "Details"], ["settings-appearance-light", "Themes & settings"], ["live-halloween", "Halloween"],
  ];

  const grid = document.getElementById("themeGrid");
  THEMES.forEach(([id, name]) => {
    const b = document.createElement("button");
    b.className = "theme";
    b.innerHTML = `<img src="images/themes/${id}.jpg" alt="${name}" loading="lazy"><span>${name}</span><em class="play">▶ Play</em>`;
    b.addEventListener("click", () => {
      const img = b.querySelector("img");
      const on = b.classList.toggle("on");
      img.src = `images/themes/${id}.${on ? "gif" : "jpg"}`;
    });
    grid.appendChild(b);
  });

  const tabs = document.getElementById("shotTabs"), img = document.getElementById("shotImg");
  function show(i) {
    const [file, label] = SHOTS[i];
    img.src = `images/ui/${file}.png`;
    img.alt = `Hubbub ${label} screen`;
    [...tabs.children].forEach((t, j) => t.setAttribute("aria-selected", String(i === j)));
  }
  SHOTS.forEach(([, label], i) => {
    const t = document.createElement("button");
    t.textContent = label; t.setAttribute("role", "tab");
    t.addEventListener("click", () => show(i));
    tabs.appendChild(t);
  });
  show(0);

  fetch("https://api.github.com/repos/karakayautku4/hubbub/releases/latest")
    .then(r => (r.ok ? r.json() : null))
    .then(j => { if (j && j.tag_name) document.getElementById("ver").textContent = `Version ${j.tag_name.replace(/^v/, "")}`; })
    .catch(() => {});
})();
