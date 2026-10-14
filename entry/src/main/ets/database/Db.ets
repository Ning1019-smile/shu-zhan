import { relationalStore } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import {
  Course, Chapter, Goal, Term, Question, SearchHit,
  TermBrief, CourseStats,
  BackupFile, BackupCourse, BackupChapter, BackupGoal, BackupTerm, BackupQuestion
} from '../model/Models';

const SQL_CREATE_COURSE = `CREATE TABLE IF NOT EXISTS course (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  created_at TEXT NOT NULL
)`;

const SQL_CREATE_CHAPTER = `CREATE TABLE IF NOT EXISTS chapter (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  course_id INTEGER NOT NULL,
  parent_id INTEGER NOT NULL DEFAULT 0,
  title TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0
)`;

const SQL_CREATE_GOAL = `CREATE TABLE IF NOT EXISTS goal (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  chapter_id INTEGER NOT NULL,
  content TEXT NOT NULL,
  done INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0
)`;

const SQL_CREATE_TERM = `CREATE TABLE IF NOT EXISTS term (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  chapter_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  definition TEXT NOT NULL DEFAULT '',
  page_no TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0
)`;

const SQL_CREATE_QUESTION = `CREATE TABLE IF NOT EXISTS question (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  chapter_id INTEGER NOT NULL,
  content TEXT NOT NULL,
  answer TEXT NOT NULL DEFAULT '',
  mastery INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0
)`;

class DbService {
  private rdb?: relationalStore.RdbStore;
  private initPromise?: Promise<void>;

  // 幂等初始化：页面和入口都可以安全调用
  async ensureReady(context: Context): Promise<void> {
    if (this.rdb) {
      return;
    }
    if (!this.initPromise) {
      this.initPromise = this.doInit(context);
    }
    await this.initPromise;
  }

  private async doInit(context: Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: 'reader_workbench.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.rdb = await relationalStore.getRdbStore(context, config);
    await this.rdb.executeSql(SQL_CREATE_COURSE);
    await this.rdb.executeSql(SQL_CREATE_CHAPTER);
    await this.rdb.executeSql(SQL_CREATE_GOAL);
    await this.rdb.executeSql(SQL_CREATE_TERM);
    await this.rdb.executeSql(SQL_CREATE_QUESTION);
  }

  private s(): relationalStore.RdbStore {
    if (!this.rdb) {
      throw new Error('数据库尚未初始化');
    }
    return this.rdb;
  }

  // ---------- 课程 ----------

  async getCourses(): Promise<Course[]> {
    const rs = await this.s().querySql('SELECT id, name, created_at FROM course ORDER BY id');
    const out: Course[] = [];
    while (rs.goToNextRow()) {
      const c: Course = {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        createdAt: rs.getString(rs.getColumnIndex('created_at'))
      };
      out.push(c);
    }
    rs.close();
    return out;
  }

  async addCourse(name: string): Promise<number> {
    const bucket: relationalStore.ValuesBucket = { 'name': name, 'created_at': new Date().toISOString() };
    return await this.s().insert('course', bucket);
  }

  async renameCourse(id: number, name: string): Promise<void> {
    await this.s().executeSql('UPDATE course SET name = ? WHERE id = ?', [name, id]);
  }

  async deleteCourse(id: number): Promise<void> {
    const s = this.s();
    await s.executeSql(`DELETE FROM goal WHERE chapter_id IN (SELECT id FROM chapter WHERE course_id = ?)`, [id]);
    await s.executeSql(`DELETE FROM term WHERE chapter_id IN (SELECT id FROM chapter WHERE course_id = ?)`, [id]);
    await s.executeSql(`DELETE FROM question WHERE chapter_id IN (SELECT id FROM chapter WHERE course_id = ?)`, [id]);
    await s.executeSql(`DELETE FROM chapter WHERE course_id = ?`, [id]);
    await s.executeSql(`DELETE FROM course WHERE id = ?`, [id]);
  }

  // ---------- 章节（树） ----------

  async getChapterTree(courseId: number): Promise<Chapter[]> {
    const rs = await this.s().querySql(
      'SELECT id, parent_id, title, sort_order FROM chapter WHERE course_id = ? ORDER BY sort_order, id', [courseId]);
    const list: Chapter[] = [];
    while (rs.goToNextRow()) {
      const ch: Chapter = {
        id: rs.getLong(rs.getColumnIndex('id')),
        courseId: courseId,
        parentId: rs.getLong(rs.getColumnIndex('parent_id')),
        title: rs.getString(rs.getColumnIndex('title')),
        sortOrder: rs.getLong(rs.getColumnIndex('sort_order')),
        children: []
      };
      list.push(ch);
    }
    rs.close();
    const map = new Map<number, Chapter>();
    list.forEach((c: Chapter) => map.set(c.id, c));
    const roots: Chapter[] = [];
    list.forEach((c: Chapter) => {
      const p = map.get(c.parentId);
      if (c.parentId > 0 && p) {
        p.children.push(c);
      } else {
        roots.push(c);
      }
    });
    return roots;
  }

  async addChapter(courseId: number, parentId: number, title: string): Promise<number> {
    const s = this.s();
    const rs = await s.querySql(
      'SELECT COALESCE(MAX(sort_order), 0) + 1 AS next FROM chapter WHERE course_id = ? AND parent_id = ?',
      [courseId, parentId]);
    let next = 1;
    if (rs.goToNextRow()) {
      next = rs.getLong(rs.getColumnIndex('next'));
    }
    rs.close();
    const bucket: relationalStore.ValuesBucket = {
      'course_id': courseId, 'parent_id': parentId, 'title': title, 'sort_order': next
    };
    return await s.insert('chapter', bucket);
  }

  async renameChapter(id: number, title: string): Promise<void> {
    await this.s().executeSql('UPDATE chapter SET title = ? WHERE id = ?', [title, id]);
  }

  async deleteChapter(id: number): Promise<void> {
    const s = this.s();
    // 收集同课程全部章节，BFS 找出该章节及其所有后代
    const rs = await s.querySql(
      'SELECT id, parent_id FROM chapter WHERE course_id = (SELECT course_id FROM chapter WHERE id = ?)', [id]);
    const parentOf = new Map<number, number>();
    while (rs.goToNextRow()) {
      parentOf.set(rs.getLong(rs.getColumnIndex('id')), rs.getLong(rs.getColumnIndex('parent_id')));
    }
    rs.close();
    const doomed: number[] = [];
    const queue: number[] = [id];
    while (queue.length > 0) {
      const cur = queue.shift() as number;
      doomed.push(cur);
      parentOf.forEach((p: number, cid: number) => {
        if (p === cur) {
          queue.push(cid);
        }
      });
    }
    const marks = doomed.map(() => '?').join(',');
    const args: Array<relationalStore.ValueType> = doomed;
    await s.executeSql(`DELETE FROM goal WHERE chapter_id IN (${marks})`, args);
    await s.executeSql(`DELETE FROM term WHERE chapter_id IN (${marks})`, args);
    await s.executeSql(`DELETE FROM question WHERE chapter_id IN (${marks})`, args);
    await s.executeSql(`DELETE FROM chapter WHERE id IN (${marks})`, args);
  }

  // ---------- 学习目标 ----------

  async getGoals(chapterId: number): Promise<Goal[]> {
    const rs = await this.s().querySql(
      'SELECT id, chapter_id, content, done, sort_order FROM goal WHERE chapter_id = ? ORDER BY sort_order, id',
      [chapterId]);
    const out: Goal[] = [];
    while (rs.goToNextRow()) {
      const g: Goal = {
        id: rs.getLong(rs.getColumnIndex('id')),
        chapterId: rs.getLong(rs.getColumnIndex('chapter_id')),
        content: rs.getString(rs.getColumnIndex('content')),
        done: rs.getLong(rs.getColumnIndex('done')),
        sortOrder: rs.getLong(rs.getColumnIndex('sort_order'))
      };
      out.push(g);
    }
    rs.close();
    return out;
  }

  async addGoal(chapterId: number, content: string, done: number = 0): Promise<number> {
    const rs = await this.s().querySql(
      'SELECT COALESCE(MAX(sort_order), 0) + 1 AS next FROM goal WHERE chapter_id = ?', [chapterId]);
    let next = 1;
    if (rs.goToNextRow()) {
      next = rs.getLong(rs.getColumnIndex('next'));
    }
    rs.close();
    const bucket: relationalStore.ValuesBucket = {
      'chapter_id': chapterId, 'content': content, 'done': done, 'sort_order': next
    };
    return await this.s().insert('goal', bucket);
  }

  async setGoalDone(id: number, done: number): Promise<void> {
    await this.s().executeSql('UPDATE goal SET done = ? WHERE id = ?', [done, id]);
  }

  async updateGoalContent(id: number, content: string): Promise<void> {
    await this.s().executeSql('UPDATE goal SET content = ? WHERE id = ?', [content, id]);
  }

  async deleteGoal(id: number): Promise<void> {
    await this.s().executeSql('DELETE FROM goal WHERE id = ?', [id]);
  }

  // ---------- 术语 ----------

  async getTerms(chapterId: number): Promise<Term[]> {
    const rs = await this.s().querySql(
      'SELECT id, chapter_id, name, definition, page_no, note, sort_order FROM term WHERE chapter_id = ? ORDER BY sort_order, id',
      [chapterId]);
    const out: Term[] = [];
    while (rs.goToNextRow()) {
      const t: Term = {
        id: rs.getLong(rs.getColumnIndex('id')),
        chapterId: rs.getLong(rs.getColumnIndex('chapter_id')),
        name: rs.getString(rs.getColumnIndex('name')),
        definition: rs.getString(rs.getColumnIndex('definition')),
        pageNo: rs.getString(rs.getColumnIndex('page_no')),
        note: rs.getString(rs.getColumnIndex('note')),
        sortOrder: rs.getLong(rs.getColumnIndex('sort_order'))
      };
      out.push(t);
    }
    rs.close();
    return out;
  }

  async addTerm(chapterId: number, name: string, definition: string, pageNo: string, note: string): Promise<number> {
    const rs = await this.s().querySql(
      'SELECT COALESCE(MAX(sort_order), 0) + 1 AS next FROM term WHERE chapter_id = ?', [chapterId]);
    let next = 1;
    if (rs.goToNextRow()) {
      next = rs.getLong(rs.getColumnIndex('next'));
    }
    rs.close();
    const bucket: relationalStore.ValuesBucket = {
      'chapter_id': chapterId, 'name': name, 'definition': definition,
      'page_no': pageNo, 'note': note, 'sort_order': next
    };
    return await this.s().insert('term', bucket);
  }

  async updateTerm(id: number, name: string, definition: string, pageNo: string, note: string): Promise<void> {
    await this.s().executeSql('UPDATE term SET name = ?, definition = ?, page_no = ?, note = ? WHERE id = ?',
      [name, definition, pageNo, note, id]);
  }

  async deleteTerm(id: number): Promise<void> {
    await this.s().executeSql('DELETE FROM term WHERE id = ?', [id]);
  }

  // ---------- 阅读问题 ----------

  async getQuestions(chapterId: number): Promise<Question[]> {
    const rs = await this.s().querySql(
      'SELECT id, chapter_id, content, answer, mastery, sort_order FROM question WHERE chapter_id = ? ORDER BY sort_order, id',
      [chapterId]);
    const out: Question[] = [];
    while (rs.goToNextRow()) {
      const q: Question = {
        id: rs.getLong(rs.getColumnIndex('id')),
        chapterId: rs.getLong(rs.getColumnIndex('chapter_id')),
        content: rs.getString(rs.getColumnIndex('content')),
        answer: rs.getString(rs.getColumnIndex('answer')),
        mastery: rs.getLong(rs.getColumnIndex('mastery')),
        sortOrder: rs.getLong(rs.getColumnIndex('sort_order'))
      };
      out.push(q);
    }
    rs.close();
    return out;
  }

  async addQuestion(chapterId: number, content: string, answer: string, mastery: number): Promise<number> {
    const rs = await this.s().querySql(
      'SELECT COALESCE(MAX(sort_order), 0) + 1 AS next FROM question WHERE chapter_id = ?', [chapterId]);
    let next = 1;
    if (rs.goToNextRow()) {
      next = rs.getLong(rs.getColumnIndex('next'));
    }
    rs.close();
    const bucket: relationalStore.ValuesBucket = {
      'chapter_id': chapterId, 'content': content, 'answer': answer, 'mastery': mastery, 'sort_order': next
    };
    return await this.s().insert('question', bucket);
  }

  async updateQuestionAnswer(id: number, answer: string): Promise<void> {
    await this.s().executeSql('UPDATE question SET answer = ? WHERE id = ?', [answer, id]);
  }

  async setQuestionMastery(id: number, mastery: number): Promise<void> {
    await this.s().executeSql('UPDATE question SET mastery = ? WHERE id = ?', [mastery, id]);
  }

  async deleteQuestion(id: number): Promise<void> {
    await this.s().executeSql('DELETE FROM question WHERE id = ?', [id]);
  }

  // ---------- 全局搜索（当前课程内） ----------

  async search(courseId: number, kw: string): Promise<SearchHit[]> {
    const s = this.s();
    const like = `%${kw}%`;
    const out: SearchHit[] = [];

    const rsGoal = await s.querySql(
      `SELECT g.content, g.chapter_id, c.title FROM goal g
       JOIN chapter c ON c.id = g.chapter_id
       WHERE c.course_id = ? AND g.content LIKE ? ORDER BY c.id, g.sort_order`, [courseId, like]);
    while (rsGoal.goToNextRow()) {
      const h: SearchHit = {
        kind: '目标', text: rsGoal.getString(0),
        chapterId: rsGoal.getLong(1), chapterTitle: rsGoal.getString(2)
      };
      out.push(h);
    }
    rsGoal.close();

    const rsTerm = await s.querySql(
      `SELECT t.name, t.chapter_id, c.title FROM term t
       JOIN chapter c ON c.id = t.chapter_id
       WHERE c.course_id = ? AND (t.name LIKE ? OR t.definition LIKE ?) ORDER BY c.id, t.sort_order`,
      [courseId, like, like]);
    while (rsTerm.goToNextRow()) {
      const h: SearchHit = {
        kind: '术语', text: rsTerm.getString(0),
        chapterId: rsTerm.getLong(1), chapterTitle: rsTerm.getString(2)
      };
      out.push(h);
    }
    rsTerm.close();

    const rsQ = await s.querySql(
      `SELECT q.content, q.chapter_id, c.title FROM question q
       JOIN chapter c ON c.id = q.chapter_id
       WHERE c.course_id = ? AND (q.content LIKE ? OR q.answer LIKE ?) ORDER BY c.id, q.sort_order`,
      [courseId, like, like]);
    while (rsQ.goToNextRow()) {
      const h: SearchHit = {
        kind: '问题', text: rsQ.getString(0),
        chapterId: rsQ.getLong(1), chapterTitle: rsQ.getString(2)
      };
      out.push(h);
    }
    rsQ.close();
    return out;
  }

  // ---------- 全书术语速查 / 统计 / 章节排序 ----------

  async getAllTerms(courseId: number): Promise<TermBrief[]> {
    const rs = await this.s().querySql(
      `SELECT t.id, t.name, t.definition, t.page_no, t.chapter_id, c.title
       FROM term t JOIN chapter c ON c.id = t.chapter_id
       WHERE c.course_id = ? ORDER BY c.id, t.sort_order, t.id`, [courseId]);
    const out: TermBrief[] = [];
    while (rs.goToNextRow()) {
      const t: TermBrief = {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        definition: rs.getString(rs.getColumnIndex('definition')),
        pageNo: rs.getString(rs.getColumnIndex('page_no')),
        chapterId: rs.getLong(rs.getColumnIndex('chapter_id')),
        chapterTitle: rs.getString(rs.getColumnIndex('title'))
      };
      out.push(t);
    }
    rs.close();
    return out;
  }

  async getCourseStats(courseId: number): Promise<CourseStats> {
    const rs = await this.s().querySql(
      `SELECT
        (SELECT COUNT(*) FROM chapter WHERE course_id = ? AND parent_id = 0) AS chapters,
        (SELECT COUNT(*) FROM goal g JOIN chapter c ON c.id = g.chapter_id WHERE c.course_id = ?) AS goals,
        (SELECT COUNT(*) FROM goal g JOIN chapter c ON c.id = g.chapter_id WHERE c.course_id = ? AND g.done = 1) AS goalsDone,
        (SELECT COUNT(*) FROM term t JOIN chapter c ON c.id = t.chapter_id WHERE c.course_id = ?) AS terms,
        (SELECT COUNT(*) FROM question q JOIN chapter c ON c.id = q.chapter_id WHERE c.course_id = ?) AS questions,
        (SELECT COUNT(*) FROM question q JOIN chapter c ON c.id = q.chapter_id WHERE c.course_id = ? AND q.mastery = 2) AS qMastered,
        (SELECT COUNT(*) FROM question q JOIN chapter c ON c.id = q.chapter_id WHERE c.course_id = ? AND q.mastery = 1) AS qFuzzy`,
      [courseId, courseId, courseId, courseId, courseId, courseId, courseId]);
    const out: CourseStats = { chapters: 0, goals: 0, goalsDone: 0, terms: 0, questions: 0, qMastered: 0, qFuzzy: 0 };
    if (rs.goToNextRow()) {
      out.chapters = rs.getLong(rs.getColumnIndex('chapters'));
      out.goals = rs.getLong(rs.getColumnIndex('goals'));
      out.goalsDone = rs.getLong(rs.getColumnIndex('goalsDone'));
      out.terms = rs.getLong(rs.getColumnIndex('terms'));
      out.questions = rs.getLong(rs.getColumnIndex('questions'));
      out.qMastered = rs.getLong(rs.getColumnIndex('qMastered'));
      out.qFuzzy = rs.getLong(rs.getColumnIndex('qFuzzy'));
    }
    rs.close();
    return out;
  }

  async updateChapterOrder(id: number, sortOrder: number): Promise<void> {
    await this.s().executeSql('UPDATE chapter SET sort_order = ? WHERE id = ?', [sortOrder, id]);
  }

  // ---------- 导出 / 导入 ----------

  async exportJson(): Promise<string> {
    const out: BackupFile = { app: 'reader-workbench', version: 1, exportedAt: new Date().toISOString(), courses: [] };
    const courses = await this.getCourses();
    for (const c of courses) {
      const bc: BackupCourse = { name: c.name, chapters: [] };
      const tree = await this.getChapterTree(c.id);
      for (const ch of tree) {
        const bk: BackupChapter = {};
        await this.fillBackupChapter(ch, bk);
        (bc.chapters as BackupChapter[]).push(bk);
      }
      (out.courses as BackupCourse[]).push(bc);
    }
    return JSON.stringify(out, null, 2);
  }

  private async fillBackupChapter(ch: Chapter, target: BackupChapter): Promise<void> {
    target.title = ch.title;
    const goals = await this.getGoals(ch.id);
    target.goals = goals.map((g: Goal): BackupGoal => ({ content: g.content, done: g.done }));
    const terms = await this.getTerms(ch.id);
    target.terms = terms.map((t: Term): BackupTerm => ({
      name: t.name, definition: t.definition, pageNo: t.pageNo, note: t.note
    }));
    const qs = await this.getQuestions(ch.id);
    target.questions = qs.map((q: Question): BackupQuestion => ({
      content: q.content, answer: q.answer, mastery: q.mastery
    }));
    target.children = [];
    for (const kid of ch.children) {
      const bk: BackupChapter = {};
      (target.children as BackupChapter[]).push(bk);
      await this.fillBackupChapter(kid, bk);
    }
  }

  // 导入 = 覆盖全部现有数据
  async importJson(text: string): Promise<void> {
    const s = this.s();
    const data = JSON.parse(text) as BackupFile;
    const courses = data && data.courses ? data.courses : null;
    if (courses === null || !Array.isArray(courses)) {
      throw new Error('备份文件格式不正确');
    }
    await s.executeSql('DELETE FROM goal');
    await s.executeSql('DELETE FROM term');
    await s.executeSql('DELETE FROM question');
    await s.executeSql('DELETE FROM chapter');
    await s.executeSql('DELETE FROM course');
    for (const c of courses) {
      const courseId = await this.addCourse(c.name ?? '未命名课程');
      const chapters = c.chapters ?? [];
      for (const ch of chapters) {
        await this.importChapter(courseId, 0, ch);
      }
    }
  }

  private async importChapter(courseId: number, parentId: number, src: BackupChapter): Promise<void> {
    const chId = await this.addChapter(courseId, parentId, src.title ?? '未命名章节');
    for (const g of (src.goals ?? [])) {
      await this.addGoal(chId, g.content ?? '', g.done === 1 ? 1 : 0);
    }
    for (const t of (src.terms ?? [])) {
      await this.addTerm(chId, t.name ?? '', t.definition ?? '', t.pageNo ?? '', t.note ?? '');
    }
    for (const q of (src.questions ?? [])) {
      const m = q.mastery ?? 0;
      const mastery = m < 0 ? 0 : (m > 2 ? 2 : m);
      await this.addQuestion(chId, q.content ?? '', q.answer ?? '', mastery);
    }
    for (const kid of (src.children ?? [])) {
      await this.importChapter(courseId, chId, kid);
    }
  }
}

// 全局单例
export const db: DbService = new DbService();
