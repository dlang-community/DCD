/*  This file is part of the Kate project.
 *
 *  Copyright (C) 2012 Christoph Cullmann <cullmann@kde.org>
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

#include "katedcdcompletion.h"
#include "katedcdplugin.h"

#include <ktexteditor/document.h>

#include <klocale.h>
#include <kicon.h>
#include <kprocess.h>

KateDcdCompletion::KateDcdCompletion (KateDcdPlugin *plugin)
  : KTextEditor::CodeCompletionModel (0)
  , m_plugin (plugin)
  , m_port(4242)
{
    kWarning() << "DCD Created KateDcdCompletion";
}

KateDcdCompletion::~KateDcdCompletion ()
{
}

QVariant KateDcdCompletion::data(const QModelIndex& index, int role) const
{
  if( role == InheritanceDepth )
    return 1;

  if( !index.parent().isValid() ) {
    //It is the group header
    switch ( role )
    {
      case Qt::DisplayRole:
        return i18n("DCD Completion");
      case GroupRole:
        return Qt::DisplayRole;
    }
  }

  if( index.column() == KTextEditor::CodeCompletionModel::Name && role == Qt::DisplayRole )
    return m_matches.item ( index.row() )->data (Qt::DisplayRole);

  if( index.column() == KTextEditor::CodeCompletionModel::Icon && role == Qt::DecorationRole ) {
    static QIcon icon(KIcon("insert-text").pixmap(QSize(16, 16)));
    return icon;
  }

  return QVariant();
}

QModelIndex KateDcdCompletion::parent(const QModelIndex& index) const
{
  if(index.internalId())
    return createIndex(0, 0, 0);
  else
    return QModelIndex();
}

QModelIndex KateDcdCompletion::index(int row, int column, const QModelIndex& parent) const
{
  if( !parent.isValid()) {
    if(row == 0)
      return createIndex(row, column, 0);
    else
      return QModelIndex();

  }else if(parent.parent().isValid())
    return QModelIndex();


  if (row < 0 || row >= m_matches.rowCount() || column < 0 || column >= ColumnCount )
    return QModelIndex();

  return createIndex(row, column, 1);
}

int KateDcdCompletion::rowCount ( const QModelIndex & parent ) const
{
  if( !parent.isValid() && !(m_matches.rowCount() == 0) )
    return 1; //One root node to define the custom group
  else if(parent.parent().isValid())
    return 0; //Completion-items have no children
  else
    return m_matches.rowCount();
}

void KateDcdCompletion::completionInvoked(KTextEditor::View* view, const KTextEditor::Range& range, InvocationType it)
{
  /**
   * auto invoke...
   */
    kWarning() << "DCD Completion Invoked";
  if (it==AutomaticInvocation) {
      if (range.columnWidth() >= 3 )
        saveMatches( view, range );
      else
        m_matches.clear();

      // done here...
      return;
  }

  // normal case ;)
  saveMatches( view, range );
}

int KateDcdCompletion::getByteOffset(const KTextEditor::View* view, const KTextEditor::Range& range)
{
    KTextEditor::Document* doc = view->document();

    int offset = 0;
    int line = range.end().line();
    for(int i = 0; i < line; ++i)
        offset += doc->lineLength(i);

    offset += range.end().column();
    return offset;
}


void KateDcdCompletion::saveMatches(KTextEditor::View* view,
                                    const KTextEditor::Range& range)
{
    kWarning() << "DCD Save Matches";
    m_matches.clear();

    size_t byteOffset = getByteOffset(view, range);
    QString filename = view->document()->url().path();
    QStringList progAndArgs;
    progAndArgs
                << QString("-c%1").arg(byteOffset)
                << QString("-p4242")
                << filename;

    QString output = callDCD(progAndArgs);

    QStringList lines = output.split('\n');
    foreach(QString line, lines)
    {
        if(line.trimmed() == "")
            continue;
        QStringList parts = line.split(' ');
        m_matches.insertRow(m_matches.rowCount(), new QStandardItem(parts.at(0)));
    }
}

QString KateDcdCompletion::callDCD(QStringList args)
{

    kWarning() << "DCD Calling dcd-client with\n"
               << args;
    KProcess proc;
    proc.setOutputChannelMode(KProcess::OnlyStdoutChannel);
    proc.setProgram("dcd-client", args);
    int returnCode = proc.execute(50);
    kWarning() << "DCD RC: " << returnCode;
    QString lines = QString(proc.readAllStandardOutput());
    kWarning() << "DCD Output " << lines;
    if(returnCode != 0)
        return "";
    return lines;
}

void KateDcdCompletion::addIncludeDir(QString path)
{
    QStringList progAndArgs;
    progAndArgs
            << QString("-p%1").arg(m_port)
            << QString("-I%1").arg(path);
    callDCD(progAndArgs);
}

void KateDcdCompletion::clearCache()
{
    QStringList progAndArgs;
    progAndArgs
                << QString("--p%1").arg(m_port)
                << "--clearCache";
    callDCD(progAndArgs);
}

// kate: space-indent on; indent-width 2; replace-tabs on;
