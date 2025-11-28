import Rom from "./rom/rom";
import backgroundData from "../data/truncated_backgrounds.dat?uint8array&base64";
import Engine from "./engine";
import BackgroundLayer from "./rom/background_layer";

const ROM = new Rom(backgroundData);
globalThis.ROM = ROM;

var setupEngine = (function setupEngine() {
  let params = getJsonFromUrl();
  let loader = null;

  let layer1Val = parseLayerParam(params.layer1, { firstLayer: true });
  let layer2Val = parseLayerParam(params.layer2, { firstLayer: false });
  let frameskip = parseFrameskipParam(params.frameskip);
  let aspectRatio = parseAspectRatioParam(params.aspectRatio);
  parseFullscreen(params.fullscreen);
  let debug = params.debug === "true";

  let fps = 30;
  let alpha = parseFloat(0.5);

  if (layer2Val === 0) {
    alpha = parseFloat(1.0);
  }

  // Create two layers
  document.BackgroundLayer = BackgroundLayer;
  const layer1 = new document.BackgroundLayer(layer1Val, ROM);
  const layer2 = new document.BackgroundLayer(layer2Val, ROM);

  // Create animation engine
  const engine = new Engine([layer1, layer2], {
    fps: fps,
    aspectRatio: aspectRatio,
    frameSkip: frameskip,
    alpha: [alpha, alpha],
    canvas: document.querySelector("canvas")
  });

  document.engine = engine;
  document.engine.animate(debug);
});
globalThis.setupEngine = setupEngine;

setupEngine();
