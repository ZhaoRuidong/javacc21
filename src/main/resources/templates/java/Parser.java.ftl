[#ftl strict_vars=true]
[#--
/* Copyright (c) 2008-2020 Jonathan Revusky, revusky@javacc.com
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright notices,
 *       this list of conditions and the following disclaimer.
 *     * Redistributions in binary formnt must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name Jonathan Revusky, Sun Microsystems, Inc.
 *       nor the names of any contributors may be used to endorse 
 *       or promote products derived from this software without specific prior written 
 *       permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */
 --]
/* Generated by: ${generated_by}. ${filename} */

[#import "ParserProductions.java.ftl" as parserCode ]
[#var parserData=grammar.parserData]
[#var hasPhase2=parserData.phase2Lookaheads?size != 0]
[#var tokenCount=grammar.lexerData.tokenCount]

[#if grammar.parserPackage?has_content]
package ${grammar.parserPackage};
[/#if]

[#if grammar.nodePackage?has_content && grammar.parserPackage! != grammar.nodePackage]
import ${grammar.nodePackage}.*;  
[/#if]
import java.util.*;
import java.io.*;

@SuppressWarnings("unused")
public class ${grammar.parserClassName} implements ${grammar.constantsClassName} {


[#if grammar.options.faultTolerant]
   private boolean tolerantParsing= true;
[#else]
    private final boolean tolerantParsing = false;
[/#if]
    public boolean isParserTolerant() {return tolerantParsing;}
    
    public void setParserTolerant(boolean tolerantParsing) {
      [#if grammar.options.faultTolerant]
        this.tolerantParsing = tolerantParsing;
      [#else]
        if (tolerantParsing) {
            throw new UnsupportedOperationException("This parser was not built with that feature!");
        } 
      [/#if]
    }

[#if grammar.options.userDefinedLexer]
  private String inputSource = "input";
  /** User defined Lexer. */
  public Lexer token_source;
[#else]
  /** Generated Lexer. */
  public ${grammar.lexerClassName} token_source;
  
  public void setInputSource(String inputSource) {
      token_source.setInputSource(inputSource);
  }
  
[/#if]

  String getInputSource() {
      return token_source.getInputSource();
  }
  
  [#if grammar.options.treeBuildingEnabled]
   [#embed "TreeBuildingCode.java.ftl"]
[/#if]

[@parserCode.ProductionsCode /]

[@parserCode.Phase2Code /]

[@parserCode.Phase3Code /]
  

  Token current_token;
[#if hasPhase2] 
  private Token jj_scanpos, jj_lastpos;
  private int jj_la;
  private boolean semanticLookahead; 
[/#if]


[#if !grammar.options.userDefinedLexer]

  public ${grammar.parserClassName}(java.io.InputStream stream) {
      this(new InputStreamReader(stream));
  }

  public ${grammar.parserClassName}(Reader reader) {
    [#if grammar.options.lexerUsesParser]
    token_source = new ${grammar.lexerClassName}(this, reader);
    [#else]
    token_source = new ${grammar.lexerClassName}(reader);
    [/#if]
    current_token = new Token();
  }
[/#if]

[#if grammar.options.userDefinedLexer]
  /** Constructor with user supplied Lexer. */
  public ${grammar.parserClassName}(Lexer lexer) {
[#else]
  /** Constructor with generated Token Manager. */
  public ${grammar.parserClassName}(${grammar.lexerClassName} lexer) {
[/#if]
    token_source = lexer;
    current_token = new Token();
  }
  
 [#if grammar.options.faultTolerant]
 
    static private boolean intArrayContains(int[] array, int elem) {
        for (int i=0; i<array.length; i++) {
            if (array[i] == elem) {
                return true;
            }
        }
        return false;
    } 
  
    /**
     * Based on the type of the node and the terminating token, we attempt to scan forward and recover. 
     */
    private void attemptRecovery(Node node, int ...finalTokenTypes) {
        int finalTokenType = finalTokenTypes[0];
        List<Token> scanAhead = getTokensToEOL(finalTokenType);
        boolean foundTerminalType = false;
        for (Token tok : scanAhead) {
            //if (tok.kind !=finalTokenType) {
            if (intArrayContains(finalTokenTypes, tok.kind)) {
               tok.setUnparsed(true);
               tok.ignored = true;
      	       node.setEndLine(tok.getEndLine());
		       node.setEndColumn(tok.getEndColumn());
		       if (tokensAreNodes) {
		           currentNodeScope.add(tok);
		       }
            } else {
                foundTerminalType = true;
            }
        }
        if (!foundTerminalType) {
	        Token lastScanned = scanAhead.get(scanAhead.size()-1);
	        Token virtualToken = null;
	        if (lastScanned.kind != finalTokenType) {
	            virtualToken = Token.newToken(finalTokenType, "VIRTUAL " + nodeNames[finalTokenType]);
	            virtualToken.setUnparsed(true);
	            virtualToken.setBeginLine(lastScanned.getEndLine());
	            virtualToken.setBeginColumn(lastScanned.getEndColumn());
	            virtualToken.setEndLine(lastScanned.getEndLine());
	            virtualToken.setEndColumn(lastScanned.getEndColumn());
	        }
	        if (tokensAreNodes) {
	        	currentNodeScope.add(virtualToken);
	        }
	        node.setEndLine(virtualToken.getEndLine());
	        node.setEndColumn(virtualToken.getEndColumn());
        }
        [#if grammar.lexerData.lexicalStates?size >1]
             token_source.doLexicalStateSwitch(finalTokenType);
        [/#if]
    }

 
     private Token consumeToken(int expectedType) throws ParseException {
        return consumeToken(expectedType, false);
     }
 
     private Token consumeToken(int expectedType, boolean forced) throws ParseException {
 [#else]
      private Token consumeToken(int expectedType) throws ParseException {
        boolean forced = false;
 [/#if]
  
        Token oldToken = current_token;
        current_token = current_token.next;
        if (current_token == null ) {
           current_token = token_source.getNextToken();
        }
[#if grammar.options.faultTolerant]        
        if (!tolerantParsing && current_token.invalidToken != null) {
            throw new ParseException(generateErrorMessage(current_token));
        }
[/#if]        
        if (current_token.kind != expectedType) {
            handleUnexpectedTokenType(expectedType, forced, oldToken) ;
        }      
     trace_token(current_token, "");
[#if grammar.options.treeBuildingEnabled]
      if (buildTree && tokensAreNodes) {
  [#if grammar.options.userDefinedLexer]
          current_token.setInputSource(inputSource);
  [/#if]
  [#if grammar.usesjjtreeOpenNodeScope]
   	      jjtreeOpenNodeScope(current_token);
  [/#if]
  [#if grammar.usesOpenNodeScopeHook]
          openNodeScopeHook(current_token);
  [/#if]          
          pushNode(current_token);
  [#if grammar.usesjjtreeCloseNodeScope]
   	      jjtreeCloseNodeScope(current_token);
  [/#if]
  [#if grammar.usesCloseNodeScopeHook]
   	      closeNodeScopeHook(current_token);
  [/#if]
      }
[/#if]
      return current_token;
  }
  
  private void handleUnexpectedTokenType( int expectedType,  boolean forced, Token oldToken) throws ParseException {
        if (!tolerantParsing) {
  //	    current_token = oldToken;
    	    throw new ParseException(generateErrorMessage(current_token));
	   } 
[#if grammar.options.faultTolerant]	   
       if (forced && tolerantParsing) {
           Token virtualToken = Token.newToken(expectedType, "");
           virtualToken.setVirtual(true);
           virtualToken.setBeginLine(oldToken.getEndLine());
           virtualToken.setBeginColumn(oldToken.getEndColumn());
           virtualToken.setEndLine(current_token.getBeginLine());
           virtualToken.setEndColumn(current_token.getBeginColumn());
           virtualToken.next = current_token;
           current_token = virtualToken;
       } else {
//	      current_token = oldToken;
	      throw new ParseException(generateErrorMessage(current_token));
      }
[/#if]      
  }
  
  
  private String generateErrorMessage(Token t) {
[#if grammar.options.faultTolerant]  
      if (t.invalidToken != null) {
          Token iv = t.invalidToken;
          return "Encountered invalid input: " + iv.image + " on line " + iv.getBeginLine() + ", column " + iv.getBeginColumn() + " of " + t.getInputSource();
      }
[/#if]      
      return "Encountered an error on (or somewhere around) line "
                + t.getBeginLine() 
                + ", column " + t.getBeginColumn() 
                + " of " + t.getInputSource();
   }
   
  
[#if hasPhase2]
  @SuppressWarnings("serial")
  static private final class LookaheadSuccess extends java.lang.Error { }
  final private LookaheadSuccess LOOKAHEAD_SUCCESS = new LookaheadSuccess();
  private boolean jj_scan_token(int kind) {
    if (jj_scanpos == jj_lastpos) {
      jj_la--;
      if (jj_scanpos.next == null) {
        jj_lastpos = jj_scanpos = jj_scanpos.next = token_source.getNextToken();
      } else {
        jj_lastpos = jj_scanpos = jj_scanpos.next;
      }
    } else {
      jj_scanpos = jj_scanpos.next;
    }
    [#if grammar.options.debugLookahead]
       trace_scan(jj_scanpos, kind);
    [/#if]

     if (jj_scanpos.kind != kind) return true;
    if (jj_la == 0 && jj_scanpos == jj_lastpos) throw LOOKAHEAD_SUCCESS;
    return false;
  }
[/#if]

  final public Token getNextToken() {
    if (current_token.next != null) current_token = current_token.next;
    else current_token = current_token.next = token_source.getNextToken();
    trace_token(current_token, " (in getNextToken)");
    return current_token;
  }

/** Get the specific Token index ahead in the stream. */
  final public Token getToken(int index) {
    Token t = current_token;
    for (int i = 0; i < index; i++) {
      if (t.next != null) t = t.next;
      else t = t.next = token_source.getNextToken();
    }
    return t;
  }
  
  private int nextTokenKind() {
    if (current_token.next == null) {
        current_token.next = token_source.getNextToken();
    }
    return current_token.next.kind;
  }
  
  private List<Token> getTokensToEOL(int desiredTokenType) {
     ArrayList<Token> result = new ArrayList<>();
     int currentLine = current_token.getBeginLine();
     Token tok = current_token;
     do  {
        Token prevToken = tok;
        if (tok.next != null) {
            tok = tok.next;
        } else {
        	tok = token_source.getNextToken();
        	prevToken.next = tok;
        }
        result.add(tok);
     } while (tok.getBeginLine() == currentLine && tok.kind != desiredTokenType && tok.kind != EOF);
     return result;
  }
  
[#if grammar.options.debugParser]
  private boolean trace_enabled = true;
 [#else]
  private boolean trace_enabled = false;
 [/#if]
 
  private int trace_indent = 0;
  
  public void  setTracingEnabled(boolean tracingEnabled) {this.trace_enabled = tracingEnabled;}
  
 /**
 * @deprecated Use #setTracingEnabled
 */
   @Deprecated
  final public void enable_tracing() {
    setTracingEnabled(true);
  }

/**
 * @deprecated Use #setTracingEnabled
 */
@Deprecated
  final public void disable_tracing() {
    setTracingEnabled(false);
  }
  
  

  private void trace_call(String s) {
    if (trace_enabled) {
      for (int i = 0; i < trace_indent; i++) {
         System.out.print(" "); 
      }
      System.out.println("Call:   " + s);
      trace_indent += 2;
    }
  }

  private void trace_return(String s) {
    if (trace_enabled) {
      trace_indent -= 2;
      for (int i = 0; i < trace_indent; i++) { 
          System.out.print(" "); 
       }
       System.out.println("Return: " + s);
    }
  }

  private void trace_token(Token t, String where) {
    if (trace_enabled) {
      for (int i = 0; i < trace_indent; i++) { System.out.print(" "); }
      System.out.print("Consumed token: <" + tokenImage[t.kind]);
      if (t.kind != 0 && !tokenImage[t.kind].equals("\"" + t.image + "\"")) {
        System.out.print(": \"" + t.image + "\"");
      }
      System.out.println(" at line " + t.beginLine + 
                " column " + t.beginColumn + ">" + where);
    }
  }
[#if grammar.options.debugLookahead]
  private void trace_scan(Token token, int expectedType) {
    if (trace_enabled) {
      for (int i = 0; i < trace_indent; i++) { System.out.print(" "); }
      System.out.print("Visited token: <" + tokenImage[token.kind]);
      if (token.kind != 0 && !tokenImage[token.kind].equals("\"" + token.image + "\"")) {
        System.out.print(": \"" + token.image + "\"");
      }
      System.out.println(" at line " + token.beginLine + "" +
                " column " + token.beginColumn + ">; Expected token: <" + nodeNames[expectedType] + ">");
    }
  }
 [/#if]
}

[#list grammar.otherParserCodeDeclarations as decl]
   ${decl}
[/#list]

