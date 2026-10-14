import { common } from '@kit.AbilityKit';
import { db } from '../database/Db';
import { Course, Chapter, SearchHit, TermBrief, CourseStats } from '../model/Models';
import { GoalPane } from '../components/GoalPane';
import { TermPane } from '../components/TermPane';
import { QuestionPane } from '../components/QuestionPane';
import { exportBackup, importBackup } from '../io/Backup';

interface FlatChapter {
  id: number;
  parentId: number;
  title: string;
  depth: number;
}

interface StatRowItem {
  label: string;
  value: string;
}

function flattenChapters(src: Chapter[], parentId: number, depth: number, out: FlatChapter[]): void {
  src.forEach((c: Chapter) => {
    out.push({ id: c.id, parentId: parentId, title: c.title, depth: depth });
    flattenChapters(c.children, c.id, depth + 1, out);
  });
}

@Entry
@Component
struct Index {
  // 课程与章节
  @State courses: Course[] = [];
  @State courseId: number = -1;
  @State chapters: Chapter[] = [];
  @State flat: FlatChapter[] = [];
  @State chapterId: number = -1;
  @State chapterTitle: string = '';
  // 右栏：全书术语速查 + 统计 + 速记
  @State allTerms: TermBrief[] = [];
  @State stats: CourseStats = { chapters: 0, goals: 0, goalsDone: 0, terms: 0, questions: 0, qMastered: 0, qFuzzy: 0 };
  @State quizOpen: boolean = false;
  @State quizTerm: TermBrief | null = null;
  @State quizRevealed: boolean = false;
  // 搜索
  @State searchKey: string = '';
  @State hits: SearchHit[] = [];
  @State showHits: boolean = false;
  // 弹窗
  @State dialogOpen: boolean = false;
  @State dialogIsConfirm: boolean = false;
  @State dialogTitle: string = '';
  @State dialogMessage: string = '';
  @State dialogText: string = '';
  private dialogAction: (() => Promise<void>) | null = null;
  // 轻提示
  @State toastMsg: string = '';
  private toastTimer: number = -1;

  async aboutToAppear(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await db.ensureReady(context);
    await this.reloadCourses(-1);
  }

  // ---------- 数据加载 ----------

  private async reloadCourses(preferId: number): Promise<void> {
    this.courses = await db.getCourses();
    if (this.courses.length === 0) {
      this.courseId = -1;
      this.chapters = [];
      this.flat = [];
      this.chapterId = -1;
      this.chapterTitle = '';
      return;
    }
    const target = this.courses.find((c: Course) => c.id === preferId);
    await this.selectCourse(target ? preferId : this.courses[0].id);
  }

  private async selectCourse(id: number): Promise<void> {
    this.courseId = id;
    this.searchKey = '';
    this.showHits = false;
    await this.reloadChapters();
  }

  private async reloadChapters(): Promise<void> {
    await this.doReloadChapters();
    await this.refreshSideData();
  }

  private async doReloadChapters(): Promise<void> {
    if (this.courseId < 0) {
      this.chapters = [];
      this.flat = [];
      this.chapterId = -1;
      this.chapterTitle = '';
      return;
    }
    this.chapters = await db.getChapterTree(this.courseId);
    const next: FlatChapter[] = [];
    flattenChapters(this.chapters, 0, 0, next);
    this.flat = next;
    if (this.flat.length === 0) {
      this.chapterId = -1;
      this.chapterTitle = '';
      return;
    }
    const kept = this.flat.find((f: FlatChapter) => f.id === this.chapterId);
    if (kept) {
      this.chapterTitle = kept.title;
    } else {
      await this.selectChapter(this.flat[0].id);
    }
  }

  private async selectChapter(id: number): Promise<void> {
    const f = this.flat.find((x: FlatChapter) => x.id === id);
    this.chapterId = id;
    this.chapterTitle = f ? f.title : '';
  }

  private currentCourse(): Course | undefined {
    return this.courses.find((c: Course) => c.id === this.courseId);
  }

  // ---------- 右栏：速查 / 统计 / 速记 ----------

  private async refreshSideData(): Promise<void> {
    if (this.courseId < 0) {
      this.allTerms = [];
      this.stats = { chapters: 0, goals: 0, goalsDone: 0, terms: 0, questions: 0, qMastered: 0, qFuzzy: 0 };
      return;
    }
    this.allTerms = await db.getAllTerms(this.courseId);
    this.stats = await db.getCourseStats(this.courseId);
  }

  private startQuiz(): void {
    if (this.allTerms.length === 0) {
      this.toast('先在术语表里添加一些术语吧');
      return;
    }
    this.quizOpen = true;
    this.quizRevealed = false;
    this.quizTerm = this.allTerms[Math.floor(Math.random() * this.allTerms.length)];
  }

  private nextQuiz(): void {
    this.quizRevealed = false;
    this.quizTerm = this.allTerms[Math.floor(Math.random() * this.allTerms.length)];
  }

  // ---------- 章节拖拽排序（仅调整同层相对顺序，不改变层级） ----------

  private onItemMove(from: number, to: number): void {
    if (from === to || from < 0 || to < 0 || from >= this.flat.length) {
      return;
    }
    const arr = this.flat.slice();
    const moved: FlatChapter = arr.splice(from, 1)[0];
    arr.splice(Math.min(to, arr.length), 0, moved);
    this.flat = arr;
    this.persistChapterOrder(arr);
  }

  private async persistChapterOrder(arr: FlatChapter[]): Promise<void> {
    let ci = 0;
    const secCount = new Map<number, number>();
    for (const f of arr) {
      if (f.depth === 0) {
        ci++;
        await db.updateChapterOrder(f.id, ci);
      } else {
        const n = (secCount.get(f.parentId) ?? 0) + 1;
        secCount.set(f.parentId, n);
        await db.updateChapterOrder(f.id, n);
      }
    }
  }

  // ---------- 搜索 ----------

  private async onSearchKey(v: string): Promise<void> {
    this.searchKey = v;
    const kw = v.trim();
    if (kw === '' || this.courseId < 0) {
      this.showHits = false;
      this.hits = [];
      return;
    }
    this.hits = await db.search(this.courseId, kw);
    this.showHits = true;
  }

  private async goHit(h: SearchHit): Promise<void> {
    this.showHits = false;
    this.searchKey = '';
    await this.selectChapter(h.chapterId);
  }

  // ---------- 弹窗 / 轻提示 ----------

  private openTextDialog(title: string, initial: string, action: (t: string) => Promise<void>): void {
    this.dialogTitle = title;
    this.dialogText = initial;
    this.dialogMessage = '';
    this.dialogIsConfirm = false;
    this.dialogAction = (): Promise<void> => action(this.dialogText);
    this.dialogOpen = true;
  }

  private openConfirmDialog(title: string, message: string, action: () => Promise<void>): void {
    this.dialogTitle = title;
    this.dialogMessage = message;
    this.dialogText = '';
    this.dialogIsConfirm = true;
    this.dialogAction = (): Promise<void> => action();
    this.dialogOpen = true;
  }

  private closeDialog(): void {
    this.dialogOpen = false;
    this.dialogAction = null;
  }

  private async submitDialog(): Promise<void> {
    if (!this.dialogIsConfirm && this.dialogText.trim() === '') {
      this.toast('请输入内容');
      return;
    }
    const act = this.dialogAction;
    this.closeDialog();
    if (act) {
      try {
        await act();
      } catch (err) {
        this.toast('操作失败，请重试');
      }
    }
  }

  private toast(msg: string): void {
    this.toastMsg = msg;
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout(() => {
      this.toastMsg = '';
      this.toastTimer = -1;
    }, 2200);
  }

  // ---------- 课程操作 ----------

  private newCourse(): void {
    this.openTextDialog('新建课程', '', async (t: string): Promise<void> => {
      const id = await db.addCourse(t.trim());
      await this.reloadCourses(id);
      this.toast(`已创建课程「${t.trim()}」`);
    });
  }

  private renameCourse(): void {
    const c = this.currentCourse();
    if (!c) {
      return;
    }
    this.openTextDialog('重命名课程', c.name, async (t: string): Promise<void> => {
      await db.renameCourse(c.id, t.trim());
      await this.reloadCourses(c.id);
    });
  }

  private deleteCourse(): void {
    const c = this.currentCourse();
    if (!c) {
      return;
    }
    this.openConfirmDialog('删除课程', `将删除课程「${c.name}」及其全部章节与内容，且不可恢复。确定？`,
      async (): Promise<void> => {
        await db.deleteCourse(c.id);
        await this.reloadCourses(-1);
        this.toast('课程已删除');
      });
  }

  // ---------- 章节操作 ----------

  private addChapter(isChild: boolean): void {
    if (this.courseId < 0) {
      this.toast('请先创建课程');
      return;
    }
    if (isChild && this.chapterId < 0) {
      this.toast('请先选择一个章节');
      return;
    }
    this.openTextDialog(isChild ? '添加小节' : '添加章节', '', async (t: string): Promise<void> => {
      await db.addChapter(this.courseId, isChild ? this.chapterId : 0, t.trim());
      await this.reloadChapters();
    });
  }

  private renameChapter(): void {
    if (this.chapterId < 0) {
      this.toast('请先选择一个章节');
      return;
    }
    const id = this.chapterId;
    this.openTextDialog('重命名章节', this.chapterTitle, async (t: string): Promise<void> => {
      await db.renameChapter(id, t.trim());
      await this.reloadChapters();
    });
  }

  private deleteChapter(): void {
    if (this.chapterId < 0) {
      this.toast('请先选择一个章节');
      return;
    }
    const id = this.chapterId;
    const title = this.chapterTitle;
    this.openConfirmDialog('删除章节', `将删除章节「${title}」及其全部小节与内容，且不可恢复。确定？`,
      async (): Promise<void> => {
        await db.deleteChapter(id);
        this.chapterId = -1;
        await this.reloadChapters();
        this.toast('章节已删除');
      });
  }

  // ---------- 备份 ----------

  private async doExport(): Promise<void> {
    if (this.courseId < 0) {
      this.toast('没有可导出的数据');
      return;
    }
    try {
      const json = await db.exportJson();
      const ok = await exportBackup(json);
      this.toast(ok ? '已导出备份文件' : '已取消导出');
    } catch (err) {
      this.toast('导出失败，请重试');
    }
  }

  private async doImport(): Promise<void> {
    try {
      const text = await importBackup();
      if (text === null) {
        return;
      }
      this.openConfirmDialog('导入备份', '导入将覆盖当前全部数据（所有课程），确定继续？',
        async (): Promise<void> => {
          await db.importJson(text);
          await this.reloadCourses(-1);
          this.toast('导入完成');
        });
    } catch (err) {
      this.toast('读取文件失败，请重试');
    }
  }

  // ---------- UI ----------

  @Builder
  SmallBtn(label: string, onFire: () => void, danger: boolean) {
    Text(label)
      .fontSize(14)
      .fontColor(danger ? $r('app.color.danger') : $r('app.color.text_primary'))
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(8)
      .backgroundColor($r('app.color.bg_muted'))
      .onClick(() => {
        onFire();
      })
  }

  @Builder
  TopBar() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Row({ space: 10 }) {
        Text('导读工作台').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))

        if (this.courses.length === 0) {
          Text('未创建课程').fontSize(14).fontColor($r('app.color.text_muted'))
        } else {
          Select(this.courses.map((c: Course): SelectOption => ({ value: c.name })))
            .selected(Math.max(this.courses.findIndex((c: Course) => c.id === this.courseId), 0))
            .value(this.currentCourse()?.name ?? '')
            .width(180).height(32)
            .onSelect((index: number) => {
              const c = this.courses[index];
              if (c) {
                this.selectCourse(c.id);
              }
            })
        }

        this.SmallBtn('＋ 课程', (): void => { this.newCourse(); }, false)
        if (this.courseId >= 0) {
          this.SmallBtn('✎', (): void => { this.renameCourse(); }, false)
          this.SmallBtn('✕', (): void => { this.deleteCourse(); }, true)
        }

        Blank()

        TextInput({ text: this.searchKey, placeholder: '搜索术语 / 问题 / 目标' })
          .width(230).height(32)
          .onChange((v: string) => {
            this.onSearchKey(v);
          })
        this.SmallBtn('导出', (): void => { this.doExport(); }, false)
        this.SmallBtn('导入', (): void => { this.doImport(); }, false)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.panel'))

      // 搜索结果下拉
      if (this.showHits) {
        Column() {
          if (this.hits.length === 0) {
            Text('没有匹配结果').fontSize(14).fontColor($r('app.color.text_muted')).padding(14)
          } else {
            List({ space: 2 }) {
              ForEach(this.hits, (h: SearchHit) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Text(h.kind)
                      .fontSize(12).fontColor(h.kind === '目标' ? $r('app.color.brand_text') : $r('app.color.warn_text'))
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(999)
                      .backgroundColor(h.kind === '目标' ? $r('app.color.brand_soft') : $r('app.color.warn_soft'))
                    Text(h.text).fontSize(14).fontColor($r('app.color.text_primary')).maxLines(1).layoutWeight(1)
                    Text(h.chapterTitle).fontSize(12).fontColor($r('app.color.text_muted')).maxLines(1)
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .borderRadius(6)
                  .onClick(() => {
                    this.goHit(h);
                  })
                }
              }, (h: SearchHit, i: number) => `${i}_${h.chapterId}_${h.text}`)
            }.width('100%').scrollBar(BarState.Auto)
          }
        }
        .width(420)
        .constraintSize({ maxHeight: 320 })
        .padding(6)
        .backgroundColor($r('app.color.panel'))
        .borderRadius(10)
        .border({ width: 1, color: $r('app.color.border') })
        .shadow({ radius: 12, color: '#22000000', offsetY: 4 })
        .margin({ top: 50, right: 110 })
      }
    }
    .width('100%')
  }

  @Builder
  Sidebar() {
    Column({ space: 10 }) {
      Row() {
        Text('章节').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_muted'))
        Blank()
        this.SmallBtn('＋ 章', (): void => { this.addChapter(false); }, false)
      }.width('100%')

      if (this.flat.length === 0) {
        Column({ space: 6 }) {
          Text('还没有章节').fontSize(14).fontColor($r('app.color.text_muted'))
          Text('点击右上角「＋ 章」添加第一章').fontSize(13).fontColor($r('app.color.text_muted'))
        }.width('100%').padding({ top: 24 }).alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 2 }) {
          ForEach(this.flat, (f: FlatChapter) => {
            ListItem() {
              Text(f.title)
                .fontSize(f.depth === 0 ? 15 : 14)
                .fontWeight(f.depth === 0 ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.chapterId === f.id ? $r('app.color.brand_text') : $r('app.color.text_primary'))
                .maxLines(1)
                .padding({ left: 12 + f.depth * 18, right: 8, top: 7, bottom: 7 })
                .borderRadius(8)
                .backgroundColor(this.chapterId === f.id ? $r('app.color.brand_soft') : Color.Transparent)
                .width('100%')
                .onClick(() => {
                  this.selectChapter(f.id);
                })
            }
          }, (f: FlatChapter) => `${f.id}_${f.title}`)
            .onMove((from: number, to: number): void => {
              this.onItemMove(from, to);
            })
        }
        .layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      }

      Divider().color($r('app.color.border'))
      Row({ space: 8 }) {
        this.SmallBtn('＋ 小节', (): void => { this.addChapter(true); }, false)
        this.SmallBtn('改名', (): void => { this.renameChapter(); }, false)
        this.SmallBtn('删除', (): void => { this.deleteChapter(); }, true)
      }.width('100%')
    }
    .width(240)
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.panel'))
    .border({ width: { right: 1 }, color: $r('app.color.border') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EmptyHint(big: string, small: string) {
    Column({ space: 8 }) {
      Text(big).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_muted'))
      Text(small).fontSize(14).fontColor($r('app.color.text_muted'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  Workspace() {
    Column({ space: 10 }) {
      Text(this.chapterTitle).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        .padding({ left: 16, right: 16, top: 12 })

      Tabs({ barPosition: BarPosition.Start }) {
        TabContent() {
          GoalPane({
            chapterId: this.chapterId,
            onChanged: (): void => { this.refreshSideData(); }
          })
        }.tabBar('章节目标')

        TabContent() {
          TermPane({
            chapterId: this.chapterId,
            onChanged: (): void => { this.refreshSideData(); }
          })
        }.tabBar('术语表')

        TabContent() {
          QuestionPane({
            chapterId: this.chapterId,
            onChanged: (): void => { this.refreshSideData(); }
          })
        }.tabBar('阅读问题')
      }
      .barMode(BarMode.Fixed)
      .layoutWeight(1)
      .width('100%')
    }
    .layoutWeight(1)
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  StatRow(item: StatRowItem) {
    Row({ space: 6 }) {
      Text(item.label).fontSize(13).fontColor($r('app.color.text_muted'))
      Blank()
      Text(item.value).fontSize(13).fontColor($r('app.color.text_primary'))
    }.width('100%')
  }

  @Builder
  QuickBar() {
    Column({ space: 10 }) {
      Text('学习进度').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_muted')).width('100%')
      this.StatRow({ label: '章节', value: `${this.stats.chapters}` })
      this.StatRow({ label: '术语', value: `${this.stats.terms}` })
      this.StatRow({ label: '目标达成', value: `${this.stats.goalsDone}/${this.stats.goals}` })
      Progress({ value: this.stats.goalsDone, total: Math.max(this.stats.goals, 1), type: ProgressType.Linear })
        .color($r('app.color.brand')).style({ strokeWidth: 5 }).width('100%')
      this.StatRow({
        label: '问题掌握',
        value: `已掌握 ${this.stats.qMastered} · 模糊 ${this.stats.qFuzzy} · 未读 ${this.stats.questions - this.stats.qMastered - this.stats.qFuzzy}`
      })
      Divider().color($r('app.color.border'))

      Row() {
        Text('全书术语速查').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_muted'))
        Blank()
        this.SmallBtn('速记', (): void => { this.startQuiz(); }, false)
      }.width('100%')

      if (this.allTerms.length === 0) {
        Text('暂无术语').fontSize(13).fontColor($r('app.color.text_muted')).width('100%')
      } else {
        List({ space: 2 }) {
          ForEach(this.allTerms, (t: TermBrief) => {
            ListItem() {
              Column({ space: 2 }) {
                Row({ space: 6 }) {
                  Text(t.name).fontSize(14).fontColor($r('app.color.text_primary')).maxLines(1).layoutWeight(1)
                  if (t.pageNo !== '') {
                    Text(t.pageNo).fontSize(12).fontColor($r('app.color.text_muted'))
                  }
                }.width('100%')
                Text(t.chapterTitle).fontSize(12).fontColor($r('app.color.text_muted')).maxLines(1).width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .borderRadius(6)
              .onClick(() => {
                this.selectChapter(t.chapterId);
              })
            }
          }, (t: TermBrief) => t.id.toString())
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      }
    }
    .width(220)
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.panel'))
    .border({ width: { left: 1 }, color: $r('app.color.border') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  QuizOverlay() {
    Column() {
      Column({ space: 14 }) {
        Text('术语速记').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(this.quizTerm?.name ?? '')
          .fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.brand_text'))
          .textAlign(TextAlign.Center)
          .width('100%')

        if (this.quizRevealed) {
          Column({ space: 6 }) {
            Text(this.quizTerm?.definition ?? '').fontSize(15).fontColor($r('app.color.text_primary')).width('100%')
            Row({ space: 8 }) {
              if ((this.quizTerm?.pageNo ?? '') !== '') {
                Text(`页码 ${this.quizTerm?.pageNo ?? ''}`).fontSize(13).fontColor($r('app.color.text_muted'))
              }
              Text(this.quizTerm?.chapterTitle ?? '').fontSize(13).fontColor($r('app.color.text_muted'))
            }
          }
          .width('100%')
          .padding(12)
          .borderRadius(8)
          .backgroundColor($r('app.color.bg_muted'))
          .alignItems(HorizontalAlign.Start)
        } else {
          Text('先回想它的含义，再翻面对答案').fontSize(13).fontColor($r('app.color.text_muted'))
        }

        Row({ space: 10 }) {
          Button(this.quizRevealed ? '下一个' : '翻面')
            .height(34).backgroundColor($r('app.color.brand')).fontColor($r('app.color.on_brand'))
            .onClick(() => {
              if (this.quizRevealed) {
                this.nextQuiz();
              } else {
                this.quizRevealed = true;
              }
            })
          Button('退出')
            .height(34).backgroundColor($r('app.color.bg_muted')).fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.quizOpen = false;
            })
        }.justifyContent(FlexAlign.Center).width('100%')
      }
      .padding(24)
      .width(400)
      .borderRadius(12)
      .backgroundColor($r('app.color.panel'))
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  DialogOverlay() {
    Column() {
      Column({ space: 4 }) {
        Text(this.dialogTitle).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))

        if (this.dialogIsConfirm) {
          Text(this.dialogMessage)
            .fontSize(14).fontColor($r('app.color.text_muted'))
            .margin({ top: 10 })
            .width('100%')
        } else {
          TextInput({ text: this.dialogText, placeholder: '请输入名称' })
            .maxLength(50)
            .margin({ top: 14 })
            .width('100%')
            .onChange((v: string) => {
              this.dialogText = v;
            })
            .onSubmit(() => {
              this.submitDialog();
            })
        }

        Row({ space: 10 }) {
          Button('取消')
            .height(34).backgroundColor($r('app.color.bg_muted')).fontColor($r('app.color.text_primary'))
            .onClick(() => {
              this.closeDialog();
            })
          Button(this.dialogIsConfirm ? '确定删除' : '确定')
            .height(34)
            .backgroundColor(this.dialogIsConfirm ? $r('app.color.danger') : $r('app.color.brand'))
            .fontColor(this.dialogIsConfirm ? Color.White : $r('app.color.on_brand'))
            .onClick(() => {
              this.submitDialog();
            })
        }
        .margin({ top: 20 })
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
      .padding(20)
      .width(380)
      .borderRadius(12)
      .backgroundColor($r('app.color.panel'))
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      // 点击遮罩不关闭，避免误触丢输入
    })
  }

  build() {
    Stack() {
      Column() {
        this.TopBar()
        Row() {
          this.Sidebar()
          if (this.courseId < 0) {
            this.EmptyHint('还没有课程', '点击左上角「＋ 课程」新建一门课，开始组织学习材料')
          } else if (this.chapterId < 0) {
            this.EmptyHint('还没有章节', '在左侧添加章节，开始为这一章建立目标、术语与问题')
          } else {
            this.Workspace()
          }
          this.QuickBar()
        }.layoutWeight(1).width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg'))

      if (this.dialogOpen) {
        this.DialogOverlay()
      }

      if (this.quizOpen) {
        this.QuizOverlay()
      }

      if (this.toastMsg !== '') {
        Column() {
          Blank()
          Text(this.toastMsg)
            .fontSize(14)
            .fontColor(Color.White)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor('#CC1A1A1A')
            .borderRadius(999)
            .margin({ bottom: 36 })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
