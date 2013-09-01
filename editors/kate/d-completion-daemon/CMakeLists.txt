# building separately or as part of kdesdk?
if(NOT KDE4_FOUND)
    find_package(KDE4 REQUIRED)
endif(NOT KDE4_FOUND)

include_directories (${KDE4_INCLUDES})
include_directories( ${KDE4_KIO_INCLUDES} )
include_directories( ${CMAKE_CURRENT_BINARY_DIR} )

set(dcdplugin_SRC
    katedcdplugin.cpp
    katedcdcompletion.cpp
    katedcdpluginview.cpp
)

#kde4_add_ui_files(dcdplugin_SRC kate_ctags.ui CTagsGlobalConfig.ui)

kde4_add_plugin(katedcdplugin ${dcdplugin_SRC})

target_link_libraries(katedcdplugin ${KDE4_KDECORE_LIBS} kateinterfaces ${KDE4_KTEXTEDITOR_LIBS} )

install(TARGETS katedcdplugin DESTINATION ${PLUGIN_INSTALL_DIR} )

########### install files ###############

#install(FILES ui.rc DESTINATION ${DATA_INSTALL_DIR}/kate/plugins/katedcd)
install(FILES katedcdplugin.desktop DESTINATION  ${SERVICES_INSTALL_DIR} )
