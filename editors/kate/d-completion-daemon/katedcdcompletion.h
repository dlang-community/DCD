/*  This file is part of the Kate project.
 *
 *  Copyright (C) 2010 Christoph Cullmann <cullmann@kde.org>
 *  Copyright (C) 2003 Anders Lund <anders.lund@lund.tdcadsl.dk>
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *
 *  You should have received a copy of the GNU Library General Public License
 *  along with this library; see the file COPYING.LIB.  If not, write to
 *  the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 *  Boston, MA 02110-1301, USA.
 */

#ifndef KATE_DCD_COMPLETION_H
#define KATE_DCD_COMPLETION_H

#include <ktexteditor/view.h>
#include <ktexteditor/codecompletionmodel.h>
#include <ktexteditor/codecompletionmodelcontrollerinterface.h>

#include <QStandardItemModel>

/**
 * Completion model that interacts with a dcd daemon.
 */


class KateDcdCompletion : public KTextEditor::CodeCompletionModel
{
  Q_OBJECT
  
  //Q_INTERFACES(KTextEditor::CodeCompletionModel)

  public:
    /**
     * Construct project completion.
     * @param plugin our plugin
     */
    KateDcdCompletion (class KateDcdPlugin *plugin);

    /**
     * Deconstruct project completion.
     */
    ~KateDcdCompletion ();

    /***************************************************************************
        CompletionModel
    ***************************************************************************/

    /**
     * This function is responsible to generating / updating the list of current
     * completions. The default implementation does nothing.
     *
     * When implementing this function, remember to call setRowCount() (or implement
     * rowCount()), and to generate the appropriate change notifications (for instance
     * by calling QAbstractItemModel::reset()).
     * @param view The view to generate completions for
     * @param range The range of text to generate completions for
     * */
    void completionInvoked(KTextEditor::View* view, const KTextEditor::Range& range, InvocationType invocationType);

    
    int rowCount ( const QModelIndex & parent ) const;

    QVariant data(const QModelIndex& index, int role) const;
    virtual QModelIndex index(int row, int column, const QModelIndex& parent=QModelIndex()) const;
    virtual QModelIndex parent(const QModelIndex& index) const;

    /*********
     * DCD Interface
     *********/

    unsigned short port() const { return m_port; }
    void port(unsigned short port) { m_port = port; }

    void addIncludeDir(QString path);
    void clearCache();
    void saveMatches(KTextEditor::View* view, const KTextEditor::Range& range);
    QString callDCD(QStringList args);
    static int getByteOffset(const KTextEditor::View *view, const KTextEditor::Range& range);

  private:
    /**
     * our plugin view
     */
    KateDcdPlugin *m_plugin;

    /**
     * model with matching data
     */
    QStandardItemModel m_matches;
    unsigned short m_port;
};

#endif

// kate: space-indent on; indent-width 2; replace-tabs on;
