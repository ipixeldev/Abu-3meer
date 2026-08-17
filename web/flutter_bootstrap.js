{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
    } catch (error) {
      window.dispatchEvent(new CustomEvent('fan-league-startup-error', {
        detail: error && (error.stack || error.message || error.toString()) || 'Flutter failed to start.',
      }));
      throw error;
    }
  },
});
