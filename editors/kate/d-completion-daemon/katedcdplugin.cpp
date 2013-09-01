/* Description : Kate CTags plugin
 * 
 * Copyright (C) 2008-2011 by Kare Sars <kare.sars@iki.fi>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) version 3, or any
 * later version accepted by the membership of KDE e.V. (or its
 * successor approved by the membership of KDE e.V.), which shall
 * act as a proxy defined in Section 6 of version 3 of the license.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "katedcdplugin.h"

#include <QFileInfo>
#include <KFileDialog>
#include <QLabel>
#include <QCheckBox>

#include <kmenu.h>
#include <kactioncollection.h>
#include <kstringhandler.h>
#include <kmessagebox.h>
#include <kstandarddirs.h>

#include <kpluginfactory.h>
#include <kpluginloader.h>
#include <kaboutdata.h>
#include <ktexteditor/codecompletioninterface.h>

#include "katedcdcompletion.h"

K_PLUGIN_FACTORY(KateDcdPluginFactory, registerPlugin<KateDcdPlugin>();)
K_EXPORT_PLUGIN(KateDcdPluginFactory(KAboutData("katedcd", "kate-dcd-plugin",
                                                  ki18n("DCD Plugin"), "0.2",
                                                  ki18n( "DCD Plugin"))))


KateDcdPlugin::KateDcdPlugin(QObject* parent, const QList<QVariant>&):
    Kate::Plugin ((Kate::Application*)parent)
{
    KGlobal::locale()->insertCatalog("kate-dcd-plugin");
    Kate::Application* app = application();
}


Kate::PluginConfigPage *KateDcdPlugin::configPage (uint number, QWidget *parent, const char *)
{
  if (number != 0) return 0;
  return new KateDcdConfigPage(parent, this);
}


QString KateDcdPlugin::configPageName (uint number) const
{
    if (number != 0) return QString();
    return i18n("DCD");
}


QString KateDcdPlugin::configPageFullName (uint number) const
{
    if (number != 0) return QString();
    return i18n("D-Completion-Daemon Settings");
}


KIcon KateDcdPlugin::configPageIcon (uint number) const
{
    if (number != 0) return KIcon();
    return KIcon("text-x-csrc");
}




KateDcdConfigPage::KateDcdConfigPage( QWidget* parent, KateDcdPlugin *plugin )
: Kate::PluginConfigPage( parent )
, m_plugin( plugin )
{
    QLabel* label = new QLabel("That's my config page", this);
}


void KateDcdConfigPage::apply()
{
    /*
    KConfigGroup config(KGlobal::config(), "CTags");
    config.writeEntry("GlobalCommand", m_confUi.cmdEdit->text());

    config.writeEntry("GlobalNumTargets", m_confUi.targetList->count());
    
    QString nr;
    for (int i=0; i<m_confUi.targetList->count(); i++) {
        nr = QString("%1").arg(i,3);
        config.writeEntry("GlobalTarget_"+nr, m_confUi.targetList->item(i)->text());
    }
    config.sync();*/
}


void KateDcdConfigPage::reset()
{
}


Kate::PluginView* KateDcdPlugin::createView(Kate::MainWindow *mainWindow)
{
    kDebug() << "DCD Create View";
    return new KateDcdPluginView(this, mainWindow);
}



