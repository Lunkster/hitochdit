// Klistra in i Google Sheets: Tillägg/Extensions > Apps Script.
// Publicera sedan: Distribuera > Ny distribution > Webbapp
//   Kör som: Jag  |  Vem har åtkomst: Alla
// Kopiera webbadressen (slutar på /exec) till CFG.sheet i index.html.

const KOLUMNER = ["datum", "user", "id", "scheme", "namn", "typ", "lat", "lon", "acc", "nvrid"];

function blad_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let b = ss.getSheetByName("Besok");
  if (!b) {
    b = ss.insertSheet("Besok");
    b.appendRow(KOLUMNER);
  }
  b.getRange(1, 1, 1, KOLUMNER.length).setValues([KOLUMNER]);
  return b;
}

function doPost(e) {
  const rad = JSON.parse(e.postData.contents);
  blad_().appendRow(KOLUMNER.map(k => rad[k] ?? ""));
  return ContentService.createTextOutput("ok");
}

function doGet(e) {
  const anvandare = (e.parameter.user || "").trim();
  const [, ...rader] = blad_().getDataRange().getValues();
  const svar = rader
    .filter(r => r[1] === anvandare)
    .map(r => Object.fromEntries(KOLUMNER.map((k, i) => [k, r[i]])))
    .reverse();
  return ContentService.createTextOutput(JSON.stringify(svar))
    .setMimeType(ContentService.MimeType.JSON);
}
