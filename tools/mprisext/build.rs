use cxx_qt_build::{CxxQtBuilder, PluginType, QmlModule};

fn main() {
    let builder =
        CxxQtBuilder::new_qml_module(QmlModule::new("MichaAI.Mpris").plugin_type(PluginType::Dynamic))
            .files(["src/lib.rs"]);
    // Точки входа плагина Qt (qt_plugin_instance и метаданные) объявлены в
    // C++, а cdylib от rustc экспортирует только символы Rust — Qt их не
    // находит. Переименовываем их в C++, а под настоящими именами
    // экспортируем обёртки из Rust (src/lib.rs, plugin_entry)
    let builder = unsafe {
        builder.cc_builder(|cc| {
            cc.define("qt_plugin_instance", "mprisext_qt_plugin_instance");
            cc.define("qt_plugin_query_metadata_v2", "mprisext_qt_plugin_query_metadata_v2");
        })
    };
    builder.build();
}
