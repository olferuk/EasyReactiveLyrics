//
//  ViewController.swift
//  EasyReactiveLyrics
//
//  Created by Alexandr Olferuk on 24/04/16.
//  Copyright © 2016 Alexandr Olferuk. All rights reserved.
//

import UIKit
import Alamofire
import Kanna
import RxSwift
import RxCocoa
import SwiftString

typealias HtmlExtractor = XMLElement -> String

struct AzLyrics {
    static let SearchDomain = "http://search.azlyrics.com/search.php"
    static let SearchResultsSelector = "//td[@class='text-left visitedlyr']/a"
    static let LyricsSelector = "//div[@class='col-xs-12 col-lg-8 text-center']/div[6]"

    static let SearchResultsExtractor: HtmlExtractor = { $0["href"]! }
    static let LyricsExtractor: HtmlExtractor = { $0.text?.trimmed() ?? "" }
}

class ViewController: UIViewController {
    @IBOutlet weak var searchTextField: UITextField!
    @IBOutlet weak var lyricsTextView: UITextView!

    let dispose = DisposeBag()  // Объект, который следит за подписчиками, и выгружает их из памяти, когда нужно.
                                // Чтобы не создавать его вот так везде каждый раз, пацаны придумали https://github.com/RxSwiftCommunity/NSObject-Rx
    
    var textSignals: Observable<String> {
        get {
            return self.searchTextField
                .rx_text                                            // Поток событий-строк, вводимых пользователем
                .filter { $0.characters.count > 4 }                 // Оставляем только достаточно длинные
                .throttle(0.4, scheduler: MainScheduler.instance)   // Новое событие будет сгенерировано после 0.4 сек от последней введенной буквы, ..
                .distinctUntilChanged()                             // ..и если строка в результате та же, что и была, не учитываем это.
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        textSignals                     // Ввод юзера
            .flatMap(searchRequest)     // => html-страница с поисковой выдачей
            .flatMap(getSearchResults)  // => первая ссылка на страницу со словами
            .flatMap(request)           // => html-страница со словами песни
            .flatMap(getLyrics)         // => текст песни.
            .catchError(handleError)    // Перехватываем ошибку, возникшую на любом этапе
            .bindTo(lyricsTextView.rx_text) // Привязываем результат к UI
            .addDisposableTo(dispose)       // Не забываем чистить память (есть подписка - есть и dispose).
    }
}

extension ViewController {
    /**
     Rx-обертка над сетевым запросом.

     --о|-->  В случае успеха несет next с контентом и onCompleted-терминал.
     --X--->  В случае ошибки несет терминал onError, содержащий ошибку

     - parameter uri:    Строка, представляющая URL-адрес искомой страницы
     - parameter params: Параметры, передающиеся при запросе
     */
    func request(uri: String, params: [String: String]) -> Observable<String> {
        return Observable.create { observer in
            let request = Alamofire.request(.GET, uri, parameters: params).responseString(completionHandler: { (response) in
                if let error = response.result.error {
                    observer.onError(error)
                }
                if let value = response.result.value {
                    observer.onNext(value)
                }
                observer.onCompleted()
            })
            return AnonymousDisposable { request.cancel() }
        }
    }

    func request(uri: String) -> Observable<String> {
        return request(uri, params: [:])
    }
}

extension ViewController {
    /**
     Извлекает узел из HTML-содержимого страницы, и с помощью extractor-функции достает строку-результат из узла.

     --ooo|-->  В случае успеха несет одну или несколько строк и успешное завершение.
     -----|-->  Успешное завершение без сигналов в случае отсутствия искомых узлов.
     ---X---->  В случае невозможности создать Kanna-документ из html-строки поток содержит onError.

     - parameter html:      html-строка
     - parameter selector:  x-Path узлу
     - parameter extractor: Функция, с помощью которой можно получить строку.
     */
    func getHtmlNode(html: String, selector: String, extractor: HtmlExtractor) -> Observable<String> {
        return Observable.create { observer in
            if let doc = Kanna.HTML(html: html, encoding: NSUTF8StringEncoding) {
                let nodeSet = doc.xpath(selector)
                for item in nodeSet {
                    let next = extractor(item)
                    if next != "" {
                        observer.onNext(next)
                    }
                }
                observer.onCompleted()
            }
            else {
                observer.onError(RxError.NoElements)
            }
            return AnonymousDisposable { }
        }
    }
}


extension ViewController {
    /**
     Инкапсулирует запрос к azLyrics.com
     
     - parameter query: Текстовый запрос
     
     - returns: Html-содержимое резльутата
     */
    func searchRequest(query: String) -> Observable<String> {
        return request(AzLyrics.SearchDomain, params: ["q": query])
    }
    
    /**
     Инкапсулирует получение первой ссылки из поисковой выдачи
     
     - parameter html: Html-контент
     
     - returns: Uri первой страницы
     */
    func getSearchResults(html: String) -> Observable<String> {
        return getHtmlNode(html, selector: AzLyrics.SearchResultsSelector, extractor: AzLyrics.SearchResultsExtractor).take(1)
    }
    
    /**
     Инкапсулирует получаение слов песни из html-страницы
     
     - parameter html: html-страница
     
     - returns: Слова
     */
    func getLyrics(html: String) -> Observable<String> {
        return getHtmlNode(html, selector: AzLyrics.LyricsSelector, extractor: AzLyrics.LyricsExtractor)
    }
}

extension ViewController {
    /**
     Перехватывает ошибку, уведомляет пользователя. Чтобы в целом поток данных не был терминирован, не завершает его onError/onCompleted-событиями.
     Возвращает never(), который формирует бесконечный поток:
     ----------->
     
     - parameter error: Ошибка
     
     - returns: Пустой поток.
     */
    func handleError(error: ErrorType) -> Observable<String> {
        print("The occured error is: \(error)")
        return Observable.never()
    }
}





