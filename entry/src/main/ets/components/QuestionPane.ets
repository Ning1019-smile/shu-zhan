import { db } from '../database/Db';
import { Question } from '../model/Models';

function masteryLabel(m: number): string {
  if (m === 2) {
    return '已掌握';
  }
  if (m === 1) {
    return '模糊';
  }
  return '未读';
}

// 阅读问题工作区：读后自问自答（费曼式），掌握度三档循环
@Component
export struct QuestionPane {
  @Prop @Watch('onChapterChange') chapterId: number = -1;
  @State questions: Question[] = [];
  @State draft: string = '';
  // 数据变化时通知父组件刷新统计
  onChanged: () => void = (): void => {};
  // 展开回答的条目
  @State openId: number = -1;
  @State openAnswer: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  onChapterChange(): void {
    this.openId = -1;
    this.reload();
  }

  private async reload(): Promise<void> {
    if (this.chapterId < 0) {
      this.questions = [];
      return;
    }
    this.questions = await db.getQuestions(this.chapterId);
  }

  private async add(): Promise<void> {
    const t = this.draft.trim();
    if (t === '' || this.chapterId < 0) {
      return;
    }
    this.draft = '';
    await db.addQuestion(this.chapterId, t, '', 0);
    await this.reload();
    this.onChanged();
  }

  private open(q: Question): void {
    this.openId = q.id;
    this.openAnswer = q.answer;
  }

  private async saveAnswer(): Promise<void> {
    await db.updateQuestionAnswer(this.openId, this.openAnswer.trim());
    this.openId = -1;
    await this.reload();
    this.onChanged();
  }

  private async cycleMastery(q: Question): Promise<void> {
    await db.setQuestionMastery(q.id, (q.mastery + 1) % 3);
    await this.reload();
    this.onChanged();
  }

  private async remove(q: Question): Promise<void> {
    await db.deleteQuestion(q.id);
    await this.reload();
    this.onChanged();
  }

  @Builder
  Pill(m: number) {
    Text(masteryLabel(m))
      .fontSize(12)
      .fontColor(m === 2 ? $r('app.color.brand_text') : (m === 1 ? $r('app.color.warn_text') : $r('app.color.text_muted')))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(999)
      .backgroundColor(m === 2 ? $r('app.color.brand_soft') : (m === 1 ? $r('app.color.warn_soft') : $r('app.color.bg_muted')))
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('阅读问题').fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(`共 ${this.questions.length} 题 · 点击掌握度标签切换状态`).fontSize(13).fontColor($r('app.color.text_muted'))
      }.width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.draft, placeholder: '新增一个阅读问题，如：逻辑结构和存储结构有什么区别？' })
          .height(36).layoutWeight(1)
          .onChange((v: string) => { this.draft = v; })
          .onSubmit(() => { this.add(); })
        Button('添加').height(36).backgroundColor($r('app.color.brand')).fontColor($r('app.color.on_brand')).onClick(() => { this.add(); })
      }.width('100%')

      if (this.questions.length === 0) {
        Column({ space: 6 }) {
          Text('这一章还没有阅读问题').fontSize(15).fontColor($r('app.color.text_muted'))
          Text('读前带着问题读，读后试着不看书写出答案').fontSize(13).fontColor($r('app.color.text_muted'))
        }.width('100%').padding({ top: 40 }).alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 6 }) {
          ForEach(this.questions, (q: Question, idx: number) => {
            ListItem() {
              Column({ space: 8 }) {
                Row({ space: 10 }) {
                  Text(`${idx + 1}. ${q.content}`)
                    .fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  this.Pill(q.mastery)
                  Text('✕').fontSize(14).fontColor($r('app.color.text_muted')).onClick(() => { this.remove(q); })
                }.width('100%')

                if (this.openId === q.id) {
                  TextArea({ text: this.openAnswer, placeholder: '不看书写出你的答案……' })
                    .height(88).width('100%').fontSize(14)
                    .backgroundColor($r('app.color.panel'))
                    .onChange((v: string) => { this.openAnswer = v; })
                  Row({ space: 8 }) {
                    Button('保存答案').height(30).backgroundColor($r('app.color.brand')).fontColor($r('app.color.on_brand')).onClick(() => { this.saveAnswer(); })
                    Button('收起').height(30).backgroundColor($r('app.color.bg_muted')).fontColor($r('app.color.text_primary'))
                      .onClick(() => { this.openId = -1; })
                  }.justifyContent(FlexAlign.End).width('100%')
                } else {
                  Row({ space: 8 }) {
                    if (q.answer === '') {
                      Text('还没有答案，点击写下你的回答').fontSize(13).fontColor($r('app.color.text_muted'))
                    } else {
                      Text(q.answer).fontSize(13).fontColor($r('app.color.text_muted')).maxLines(2)
                    }
                  }
                  .width('100%')
                  .onClick(() => { this.open(q); })
                }
              }
              .width('100%')
              .padding(10)
              .borderRadius(8)
              .backgroundColor($r('app.color.panel'))
              .border({ width: 1, color: $r('app.color.border') })
              .alignItems(HorizontalAlign.Start)
            }
          }, (q: Question) => `${q.id}_${q.mastery}_${q.answer.length}`)
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      }
    }
    .width('100%').height('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }
}
