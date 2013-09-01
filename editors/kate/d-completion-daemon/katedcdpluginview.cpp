#include "katedcdplugin.h"
#include "katedcdcompletion.h"

#include <ktexteditor/codecompletioninterface.h>

#include <QFileInfo>
#include <QDir>

QString pluginViewName = "kateprojectplugin";

KateDcdPluginView::KateDcdPluginView(KateDcdPlugin *plugin, Kate::MainWindow *mainWindow)
    : Kate::PluginView(mainWindow), m_plugin(plugin), m_completion(0)
{
    this->m_completion = new KateDcdCompletion(m_plugin);


    // track the project that's active for this mainWindow.
    connect(mainWindow, SIGNAL(pluginViewCreated(QString,Kate::PluginView*)),
            this, SLOT(onPluginViewCreated(QString, Kate::PluginView*)));
    connect(mainWindow, SIGNAL(pluginViewDeleted(QString,Kate::PluginView*)),
            this, SLOT(onPluginViewDeleted(QString, Kate::PluginView*)));
    m_projectPluginView = mainWindow->pluginView(pluginViewName);

    // track all views of this mainWindow and register our completion instance
    connect(mainWindow, SIGNAL(viewCreated(KTextEditor::View*)),
            this, SLOT(onViewCreated(KTextEditor::View*)));
    foreach(KTextEditor::View* view, mainWindow->views())
        onViewCreated(view);

}

KateDcdPluginView::~KateDcdPluginView()
{
    delete m_completion;
}

void KateDcdPluginView::readSessionConfig(KConfigBase *config,
                                          const QString &groupPrefix)
{
    // TODO: Use SessionConfig to configure our CompletionModel
}

void KateDcdPluginView::writeSessionConfig(KConfigBase *config,
                                           const QString &groupPrefix)
{
    // TODO: DITTO
}

void KateDcdPluginView::onViewCreated(KTextEditor::View *view)
{
    KTextEditor::CodeCompletionInterface* cci =
            dynamic_cast<KTextEditor::CodeCompletionInterface*>(view);

    if(cci)
        cci->registerCompletionModel(m_completion);
}


void KateDcdPluginView::onPluginViewCreated(QString name, Kate::PluginView *view)
{
    if(name != pluginViewName)
        return;

    m_projectPluginView = view;
    readProjectConfig();
    connect(view, SIGNAL(projectMapChanged()), this,
            SLOT(readProjectConfig()));
}

void KateDcdPluginView::onPluginViewDeleted(QString name, Kate::PluginView *view)
{
    if(name != pluginViewName)
        return;

    if(view != m_projectPluginView)
        kDebug() << "DCD old projectView was unknown.";

    m_projectPluginView = 0;
}

void KateDcdPluginView::readProjectConfig()
{
    if(!m_projectPluginView)
        return;

    QVariantMap projectMap = m_projectPluginView->property("projectMap").toMap();

    // do we have a valid map for dcd settings?
    QVariantMap dcdMap = projectMap.value("dcd").toMap();
    if (dcdMap.isEmpty()) {
        return;
    }

    // first get the port or the other changes might have no effect
    if(dcdMap.contains("port"))
    {
        m_completion->port(dcdMap.value("port").toInt());
    }

    QDir baseDir = QDir(m_projectPluginView->property("projectBaseDir").toString());
    if(dcdMap.contains("include-dirs"))
    {
        foreach (QVariant includeDir, dcdMap["include-dirs"].toList())
        {
            QFileInfo fInfo(includeDir.toString());
            QString path = fInfo.path();
            if(fInfo.isRelative())
            {
                path = baseDir.absoluteFilePath(path);
                kDebug() << "DCD: path " << path;
            }
            m_completion->addIncludeDir(path);
        }
    }
}
