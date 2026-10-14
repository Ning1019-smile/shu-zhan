// 数据模型定义：课程 → 章节 →（目标 / 术语 / 阅读问题）

export interface Course {
  id: number;
  name: string;
  createdAt: string;
}

export interface Chapter {
  id: number;
  courseId: number;
  parentId: number; // 0 表示顶级章
  title: string;
  sortOrder: number;
  children: Chapter[];
}

export interface Goal {
  id: number;
  chapterId: number;
  content: string;
  done: number; // 0 未达成 / 1 已达成
  sortOrder: number;
}

export interface Term {
  id: number;
  chapterId: number;
  name: string;
  definition: string;
  pageNo: string;
  note: string;
  sortOrder: number;
}

export interface Question {
  id: number;
  chapterId: number;
  content: string;
  answer: string;
  mastery: number; // 0 未读 / 1 模糊 / 2 已掌握
  sortOrder: number;
}

export interface SearchHit {
  kind: string; // '目标' | '术语' | '问题'
  text: string;
  chapterId: number;
  chapterTitle: string;
}

// 全书术语速查条目（跨章节）
export interface TermBrief {
  id: number;
  name: string;
  definition: string;
  pageNo: string;
  chapterId: number;
  chapterTitle: string;
}

// 课程学习统计
export interface CourseStats {
  chapters: number;
  goals: number;
  goalsDone: number;
  terms: number;
  questions: number;
  qMastered: number;
  qFuzzy: number;
}

// ---------- 备份文件结构（JSON 导入导出） ----------

export interface BackupGoal {
  content?: string;
  done?: number;
}

export interface BackupTerm {
  name?: string;
  definition?: string;
  pageNo?: string;
  note?: string;
}

export interface BackupQuestion {
  content?: string;
  answer?: string;
  mastery?: number;
}

export interface BackupChapter {
  title?: string;
  children?: BackupChapter[];
  goals?: BackupGoal[];
  terms?: BackupTerm[];
  questions?: BackupQuestion[];
}

export interface BackupCourse {
  name?: string;
  chapters?: BackupChapter[];
}

export interface BackupFile {
  app?: string;
  version?: number;
  exportedAt?: string;
  courses?: BackupCourse[];
}
